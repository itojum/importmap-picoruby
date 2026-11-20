RSpec.describe ImportmapPicoRuby::ImportMap do
  page = "https://example.com/game/index.html"

  def build(page, *jsons)
    map = described_class.new(page, SimpleUrl)
    jsons.each { |j| map.add(j) }
    map
  end

  it "resolves npm:, absolute and relative URLs" do
    map = build(page, "imports" => {
      "picodx" => "npm:picodx@1.2.0",
      "util" => "npm:util-rb@1.0.0/lib/util.rb",
      "mylib" => "https://cdn.jsdelivr.net/gh/you/mylib@abc1234/lib/mylib.rb",
      "local" => "./vendor/local.rb",
    })
    expect(map.imports).to eq(
      "picodx" => "npm-package:https://cdn.jsdelivr.net/npm/picodx@1.2.0/",
      "util" => "https://cdn.jsdelivr.net/npm/util-rb@1.0.0/lib/util.rb",
      "mylib" => "https://cdn.jsdelivr.net/gh/you/mylib@abc1234/lib/mylib.rb",
      "local" => "https://example.com/game/vendor/local.rb",
    )
    expect(map.packages).to eq(["https://cdn.jsdelivr.net/npm/picodx@1.2.0/"])
  end

  it "fills npm packages from their package.json entry" do
    map = build(page, "imports" => { "picodx" => "npm:picodx@1.2.0" })
    map.set_package_entry("https://cdn.jsdelivr.net/npm/picodx@1.2.0/", "https://cdn.jsdelivr.net/npm/picodx@1.2.0/lib/picodx.rb")
    expect(map.lookup("picodx")).to eq(["https://cdn.jsdelivr.net/npm/picodx@1.2.0/lib/picodx.rb", "picodx"])
  end

  it "looks up exact names (with or without .rb) and the longest prefix" do
    map = build(page, "imports" => {
      "a" => "https://x.test/a.rb",
      "a/" => "https://x.test/a/",
      "a/deep/" => "https://y.test/deep/",
    })
    expect(map.lookup("a")).to eq(["https://x.test/a.rb", "a"])
    expect(map.lookup("a.rb")).to eq(["https://x.test/a.rb", "a"])
    expect(map.lookup("a/b")).to eq(["https://x.test/a/b.rb", "a/"])
    expect(map.lookup("a/deep/c")).to eq(["https://y.test/deep/c.rb", "a/deep/"])
    expect(map.lookup("b")).to be_nil
    expect(map.names).to eq(["a"])
  end

  it "resolves integrity keys, loadPaths and keeps preload" do
    map = build(page, "integrity" => { "./x.rb" => "sha384-abc" }, "loadPaths" => ["./src", "lib/"], "preload" => ["plugins/*"])
    expect(map.integrity).to eq("https://example.com/game/x.rb" => "sha384-abc")
    expect(map.load_paths).to eq(["https://example.com/game/src/", "https://example.com/game/lib/"])
    expect(map.preload).to eq(["plugins/*"])
  end

  it "merges several maps, the first one winning" do
    map = build(page, { "imports" => { "a" => "./1.rb" }, "loadPaths" => ["src/"] },
                { "imports" => { "a" => "./2.rb", "b" => "./b.rb" }, "loadPaths" => ["src/", "x/"] })
    expect(map.imports).to eq("a" => "https://example.com/game/1.rb", "b" => "https://example.com/game/b.rb")
    expect(map.load_paths.size).to eq(2)
  end

  it "reports invalid entries without raising" do
    map = build(page, "imports" => { "a" => 1, "b/" => "./b.rb", "c" => "npm:" }, "loadPaths" => "src")
    expect(map.errors.size).to eq(4)
    expect(map.imports).to eq({})
    expect(build(page, []).errors).to eq(["the import map must be a JSON object"])
  end
end

RSpec.describe ImportmapPicoRuby::Layout do
  layout = described_class.new("http://localhost:8080/game/index.html", SimpleUrl)

  it "mirrors app URLs of the page's origin under /app" do
    expect(layout.path(:app, "http://localhost:8080/game/src/main.rb")).to eq("/app/game/src/main.rb")
    expect(layout.path(:app, "https://other.test/x.rb")).to eq("/app/other.test/x.rb")
  end

  it "mirrors library URLs under /lib/<host>" do
    expect(layout.path(:lib, "https://cdn.jsdelivr.net/npm/picodx@1.2.0/lib/picodx.rb")).to eq(
      "/lib/cdn.jsdelivr.net/npm/picodx@1.2.0/lib/picodx.rb"
    )
  end

  it "uses the page's directory as the working directory" do
    expect(layout.cwd).to eq("/app/game")
  end

  it "builds $LOAD_PATH" do
    lps = ["http://localhost:8080/game/src/"]
    expect(layout.load_path(lps, false)).to eq(["/lib", "/app/game/src"])
    expect(layout.load_path(lps, true)).to eq(["/lib", "/app/game/src", "/app/game"])
  end

  it "writes stubs that require the real file" do
    expect(layout.stub_path("picodx")).to eq("/lib/picodx.rb")
    expect(layout.stub_source("/lib/h/x/picodx.rb")).to eq(%(# importmap-picoruby\nrequire "/lib/h/x/picodx"\n))
  end

  it "keeps line 1 when adding the preamble" do
    out = layout.with_preamble("puts __LINE__\nputs 2\n", ["/lib"])
    expect(out.lines.size).to eq(2)
    expect(out).to start_with(%{($LOAD_PATH ||= []).replace(["/lib"]); (Dir.chdir("/app/game") rescue nil); puts __LINE__})
    expect(layout.with_preamble("=begin\n=end\n", ["/lib"]).lines[1]).to eq("=begin\n")
  end

  it "produces a preamble that CRuby can parse" do
    expect { RubyVM::InstructionSequence.compile(layout.with_preamble("# c\nx = 1\n", ["/lib", "/a"])) }.not_to raise_error
  end
end
