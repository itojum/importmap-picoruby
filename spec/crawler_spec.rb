RSpec.describe PicoRubyImportmap::Crawler do
  PAGE = "https://site.test/game/index.html"
  CDN = "https://cdn.jsdelivr.net/npm/picodx@1.2.0/"

  # server: URL => source. Records the batches it was asked for.
  def crawl(server, map_json: {}, apps: [], builtins: %w[js json], preload: [], entries: {})
    map = PicoRubyImportmap::ImportMap.new(PAGE, SimpleUrl)
    map.add(map_json)
    entries.each { |base, url| map.set_package_entry(base, url) }
    layout = PicoRubyImportmap::Layout.new(PAGE, SimpleUrl)
    crawler = described_class.new(map, layout, SimpleUrl, builtins)
    apps.each { |a| a.is_a?(Array) ? crawler.add_app(*a) : crawler.add_app(a) }
    preload.each { |p| crawler.add_preload(p) }
    @batches = []
    crawler.run do |urls|
      @batches << urls
      urls.each_with_object({}) { |u, h| h[u] = server[u] }
    end
    crawler
  end

  def files(crawler)
    crawler.files.to_h
  end

  it "fetches an npm library and writes it under /lib with a stub" do
    server = {
      "https://site.test/game/src/main.rb" => %(require "js"\nrequire "picodx"\n),
      "#{CDN}lib/picodx.rb" => "module PicoDX; end\n",
    }
    c = crawl(server,
              map_json: { "imports" => { "picodx" => "npm:picodx@1.2.0" } },
              entries: { CDN => "#{CDN}lib/picodx.rb" },
              apps: ["https://site.test/game/src/main.rb"])
    expect(files(c)).to eq(
      "/app/game/src/main.rb" => server["https://site.test/game/src/main.rb"],
      "/lib/cdn.jsdelivr.net/npm/picodx@1.2.0/lib/picodx.rb" => "module PicoDX; end\n",
      "/lib/picodx.rb" => %(# picoruby-importmap\nrequire "/lib/cdn.jsdelivr.net/npm/picodx@1.2.0/lib/picodx"\n),
    )
    expect(c.warnings).to eq([])
    expect(@batches.size).to eq(2) # main.rb, then picodx.rb (js is builtin)
  end

  it "resolves ./ against the page directory and bare names through loadPaths, in order" do
    server = {
      "https://site.test/game/src/main.rb" => <<~RUBY,
        require "./lib/enemy"
        def start
          require "scene"
        end
      RUBY
      "https://site.test/game/lib/enemy.rb" => "class Enemy; end\n",
      "https://site.test/game/scenes/scene.rb" => %(require "./lib/enemy"\n),
    }
    c = crawl(server,
              map_json: { "loadPaths" => ["./src/", "./scenes/"] },
              apps: ["https://site.test/game/src/main.rb"])
    expect(files(c).keys).to contain_exactly("/app/game/src/main.rb", "/app/game/lib/enemy.rb", "/app/game/scenes/scene.rb")
    # src/scene.rb is tried first and is missing, then scenes/scene.rb
    expect(@batches.flatten).to include("https://site.test/game/src/scene.rb")
    expect(c.missing.keys).to eq(["https://site.test/game/src/scene.rb"])
    expect(c.warnings).to eq([])
  end

  it "fetches files that do not depend on each other in the same batch" do
    server = {
      "https://site.test/game/main.rb" => %(require "./a"\nrequire "./b"\nrequire "./c"\n),
      "https://site.test/game/a.rb" => "", "https://site.test/game/b.rb" => "", "https://site.test/game/c.rb" => "",
    }
    crawl(server, apps: ["https://site.test/game/main.rb"])
    expect(@batches).to eq([["https://site.test/game/main.rb"],
                            %w[a b c].map { |x| "https://site.test/game/#{x}.rb" }])
  end

  it "fetches each file once and detects cycles" do
    server = {
      "https://site.test/game/main.rb" => %(require "./a"\n),
      "https://site.test/game/a.rb" => %(require "./b"\n),
      "https://site.test/game/b.rb" => %(require "./a"\nrequire "./main"\n),
    }
    c = crawl(server, apps: ["https://site.test/game/main.rb"])
    expect(@batches.flatten.size).to eq(3)
    expect(c.cycles).to contain_exactly(
      %w[a b a].map { |x| "https://site.test/game/#{x}.rb" },
      %w[main a b main].map { |x| "https://site.test/game/#{x}.rb" },
    )
  end

  it "keeps the relative positions of require_relative files in a library" do
    base = "https://cdn.jsdelivr.net/gh/ydah/webxr-ruby@79f501e/lib/"
    server = {
      "https://site.test/game/main.rb" => %(require "webxr"\n),
      "#{base}webxr.rb" => %(require_relative "webxr/version"\nrequire_relative "webxr/core/system"\n),
      "#{base}webxr/version.rb" => "",
      "#{base}webxr/core/system.rb" => %(require_relative "../version"\n),
    }
    c = crawl(server, map_json: { "imports" => { "webxr" => "#{base}webxr.rb" } }, apps: ["https://site.test/game/main.rb"])
    root = "/lib/cdn.jsdelivr.net/gh/ydah/webxr-ruby@79f501e/lib/"
    expect(files(c).keys).to contain_exactly(
      "/app/game/main.rb", "/lib/webxr.rb",
      "#{root}webxr.rb", "#{root}webxr/version.rb", "#{root}webxr/core/system.rb",
    )
    expect(c.uses_require_relative?).to be true
  end

  it "resolves a library's own bare requires from its lib directory" do
    server = {
      "https://site.test/game/main.rb" => %(require "picodx"\n),
      "#{CDN}lib/picodx.rb" => %(require "picodx/sprite"\n),
      "#{CDN}lib/picodx/sprite.rb" => "",
    }
    c = crawl(server, map_json: { "imports" => { "picodx" => "#{CDN}lib/picodx.rb" } }, apps: ["https://site.test/game/main.rb"])
    expect(files(c)).to include(
      "/lib/picodx/sprite.rb" => %(# picoruby-importmap\nrequire "/lib/cdn.jsdelivr.net/npm/picodx@1.2.0/lib/picodx/sprite"\n),
    )
  end

  it "uses prefix mappings" do
    server = {
      "https://site.test/game/main.rb" => %(require "ui/button"\n),
      "https://site.test/vendor/ui/button.rb" => "",
    }
    c = crawl(server, map_json: { "imports" => { "ui/" => "../vendor/ui/" } }, apps: ["https://site.test/game/main.rb"])
    expect(files(c).keys).to include("/lib/site.test/vendor/ui/button.rb", "/lib/ui/button.rb")
  end

  it "warns about requires it cannot resolve or fetch, without failing" do
    server = { "https://site.test/game/main.rb" => %(require "nope"\nrequire "./gone"\nrequire "js"\n) }
    c = crawl(server, apps: ["https://site.test/game/main.rb"])
    expect(c.warnings.size).to eq(2)
    expect(c.warnings[0]).to include('require "nope"', "main.rb:1")
    expect(c.warnings[1]).to include("gone.rb", "main.rb:2")
    expect(c.errors).to eq([])
  end

  it "reports the same problem once, listing where it comes from" do
    server = {
      "https://site.test/game/main.rb" => %(require "set"\nrequire "./a"\nrequire "./b"\n),
      "https://site.test/game/a.rb" => %(require "set"\n),
      "https://site.test/game/b.rb" => %(require "set"\n),
    }
    c = crawl(server, apps: ["https://site.test/game/main.rb"])
    expect(c.warnings).to eq([
      'require "set": no import map entry or load path matches; it is left to PicoRuby\'s require at run time ' \
      "(from https://site.test/game/main.rb:1, https://site.test/game/a.rb:1, https://site.test/game/b.rb:1)",
    ])
  end

  it "does not look up other libraries' names in a library's lib directory" do
    server = {
      "https://site.test/game/main.rb" => %(require "picodx"\n),
      "#{CDN}lib/picodx.rb" => %(require "set"\nrequire "picodx_extra"\n),
    }
    c = crawl(server, map_json: { "imports" => { "picodx" => "#{CDN}lib/picodx.rb" } }, apps: ["https://site.test/game/main.rb"])
    expect(@batches.flatten).not_to include("#{CDN}lib/set.rb", "#{CDN}lib/picodx_extra.rb")
    expect(c.warnings.size).to eq(2)
  end

  it "reports an app script it cannot fetch as an error" do
    c = crawl({}, apps: ["https://site.test/game/missing.rb"])
    expect(c.errors.size).to eq(1)
  end

  it "scans inline app scripts and does not write them as files" do
    server = { "https://site.test/game/a.rb" => "" }
    c = crawl(server, apps: [["#{PAGE}#ruby-app-1", %(require "./a"\n)]])
    expect(files(c).keys).to eq(["/app/game/a.rb"])
  end

  it "preloads names, with globs over import map names" do
    server = {
      "https://site.test/p/a.rb" => "", "https://site.test/p/b.rb" => "", "https://site.test/game/src/dyn.rb" => "",
    }
    c = crawl(server,
              map_json: { "imports" => { "plugins/a" => "/p/a.rb", "plugins/b" => "/p/b.rb", "other" => "/o.rb" },
                          "loadPaths" => ["src/"] },
              preload: ["plugins/*", "dyn", "nothing/*"])
    expect(files(c).keys).to contain_exactly("/lib/plugins/a.rb", "/lib/plugins/b.rb", "/lib/site.test/p/a.rb",
                                             "/lib/site.test/p/b.rb", "/app/game/src/dyn.rb")
    expect(c.warnings.size).to eq(1)
    expect(c.warnings[0]).to include("nothing/*")
  end

  it "ignores builtins, absolute paths and .mrb" do
    server = { "https://site.test/game/main.rb" => %(require "json"\nrequire "/lib/x"\nrequire "a.mrb"\n) }
    c = crawl(server, apps: ["https://site.test/game/main.rb"], map_json: { "loadPaths" => ["src/"] })
    expect(@batches.flatten).to eq(["https://site.test/game/main.rb"])
    expect(c.warnings).to eq([])
  end
end
