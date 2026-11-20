RSpec.describe PicoRubyImportmap::Glob do
  it "matches * within one path segment" do
    expect(described_class.match?("plugins/*", "plugins/a")).to be true
    expect(described_class.match?("plugins/*", "plugins/a/b")).to be false
    expect(described_class.match?("plugins/*", "other/a")).to be false
    expect(described_class.match?("*.rb", "a.rb")).to be true
  end

  it "matches ** across segments" do
    expect(described_class.match?("plugins/**", "plugins/a/b")).to be true
    expect(described_class.match?("**/x", "a/b/x")).to be true
    expect(described_class.match?("**/x", "x")).to be true
    expect(described_class.match?("a/**/x", "a/x")).to be true
  end

  it "matches ? as one character" do
    expect(described_class.match?("a?c", "abc")).to be true
    expect(described_class.match?("a?c", "a/c")).to be false
  end

  it ".glob? detects patterns" do
    expect(described_class.glob?("a/*")).to be true
    expect(described_class.glob?("a/b")).to be false
  end
end

RSpec.describe PicoRubyImportmap::Npm do
  describe ".split" do
    it "expands to jsDelivr" do
      expect(described_class.split("npm:picodx@1.2.0")).to eq(["https://cdn.jsdelivr.net/npm/picodx@1.2.0/", ""])
      expect(described_class.split("npm:picodx@1.2.0/lib/picodx.rb")).to eq(
        ["https://cdn.jsdelivr.net/npm/picodx@1.2.0/", "lib/picodx.rb"]
      )
    end

    it "handles scoped packages" do
      expect(described_class.split("npm:@me/lib@2.0.0/src/a.rb")).to eq(
        ["https://cdn.jsdelivr.net/npm/@me/lib@2.0.0/", "src/a.rb"]
      )
    end

    it "rejects broken specifiers" do
      expect { described_class.split("npm:") }.to raise_error(ArgumentError)
      expect { described_class.split("npm:x@") }.to raise_error(ArgumentError)
    end
  end

  describe ".entry" do
    it "prefers picoruby (string)" do
      expect(described_class.entry("picoruby" => "./lib/a.rb", "main" => "index.js")).to eq("lib/a.rb")
    end

    it "accepts picoruby.main" do
      expect(described_class.entry("picoruby" => { "main" => "lib/b.rb" })).to eq("lib/b.rb")
    end

    it "falls back to main only when it is a .rb file" do
      expect(described_class.entry("main" => "lib/picodx.rb")).to eq("lib/picodx.rb")
      expect(described_class.entry("main" => "index.js")).to be_nil
      expect(described_class.entry({})).to be_nil
    end
  end
end

RSpec.describe PicoRubyImportmap::Pinned do
  it "treats exact npm versions as pinned" do
    expect(described_class.pinned?("https://cdn.jsdelivr.net/npm/picodx@1.2.0/lib/picodx.rb")).to be true
    expect(described_class.pinned?("https://cdn.jsdelivr.net/npm/@me/x@1.0.0-beta.1/a.rb")).to be true
  end

  it "does not pin ranges, tags or missing versions" do
    expect(described_class.pinned?("https://cdn.jsdelivr.net/npm/picodx@1/lib/picodx.rb")).to be false
    expect(described_class.pinned?("https://cdn.jsdelivr.net/npm/picodx@latest/a.rb")).to be false
    expect(described_class.pinned?("https://cdn.jsdelivr.net/npm/picodx/a.rb")).to be false
  end

  it "pins GitHub commits and version tags" do
    expect(described_class.pinned?("https://cdn.jsdelivr.net/gh/you/mylib@abc1234/lib/mylib.rb")).to be true
    expect(described_class.pinned?("https://cdn.jsdelivr.net/gh/you/mylib@v1.2.3/lib/mylib.rb")).to be true
    expect(described_class.pinned?("https://cdn.jsdelivr.net/gh/you/mylib@main/lib/mylib.rb")).to be false
  end

  it "does not pin other hosts" do
    expect(described_class.pinned?("https://example.com/npm/x@1.0.0/a.rb")).to be false
  end
end

RSpec.describe PicoRubyImportmap::Integrity do
  it "picks the strongest algorithm" do
    expect(described_class.parse("sha256-aaa sha384-bbb sha384-ccc")).to eq(["SHA-384", %w[bbb ccc]])
    expect(described_class.parse("sha512-x")).to eq(["SHA-512", ["x"]])
  end

  it "ignores unknown algorithms" do
    expect(described_class.parse("md5-x")).to be_nil
  end

  it "makes a cache key per integrity value" do
    expect(described_class.cache_key("https://a.test/x.rb", nil)).to eq("https://a.test/x.rb")
    expect(described_class.cache_key("https://a.test/x.rb", "sha384-AB+/=")).to eq(
      "https://a.test/x.rb?picoruby-importmap-integrity=sha384-AB+/="
    )
  end
end
