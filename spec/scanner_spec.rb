RSpec.describe ImportmapPicoRuby::Scanner do
  def scan(src)
    described_class.scan(src)
  end

  def paths(src)
    scan(src).map { |r| [r[:kind], r[:path]] }
  end

  describe "calls it finds" do
    it "finds require, require_relative and load with string literals" do
      src = <<~RUBY
        require "a"
        require 'b'
        require_relative "./c"
        load "d.rb"
      RUBY
      expect(paths(src)).to eq([[:require, "a"], [:require, "b"], [:require_relative, "./c"], [:load, "d.rb"]])
    end

    it "accepts parentheses, with spaces and newlines inside" do
      expect(paths(%{require("a")\nrequire( 'b' )\nrequire(\n  "c"\n)})).to eq(
        [[:require, "a"], [:require, "b"], [:require, "c"]]
      )
    end

    it "accepts %q and % literals" do
      expect(paths(%{require %q|a|\nrequire %(b)})).to eq([[:require, "a"], [:require, nil]])
    end

    it "finds calls inside methods, blocks, conditionals and modifiers" do
      src = <<~RUBY
        def load_scene
          require "scene"
        end
        [1].each { |x| require "in_block" }
        if ENV
          require "in_if"
        else
          require_relative "in_else"
        end
        require "modifier" if defined?(Foo)
        x = (require "in_parens")
        class A; def b = require("endless"); end
      RUBY
      expect(scan(src).map { |r| r[:path] }).to eq(%w[scene in_block in_if in_else modifier in_parens endless])
    end

    it "records the line of each call" do
      src = "\n\nrequire 'a'\n  require 'b'\n"
      expect(scan(src).map { |r| r[:line] }).to eq([3, 4])
    end

    it "reports a call without a plain string literal with path nil" do
      src = <<~'RUBY'
        require name
        require "plugins/#{name}"
        load(path)
      RUBY
      expect(paths(src)).to eq([[:require, nil], [:require, nil], [:load, nil]])
    end

    it "keeps escaped quotes in literals" do
      expect(paths(%q{require "a\"b"})).to eq([[:require, 'a"b']])
    end

    it "finds requires inside string interpolation code" do
      expect(paths(%q{x = "#{require 'a'}"})).to eq([[:require, "a"]])
    end
  end

  describe "what it skips" do
    it "skips comments" do
      expect(paths("# require 'a'\nx = 1 # require 'b'\n")).to eq([])
    end

    it "skips strings" do
      src = %q{puts "require 'a'"; puts 'require "b"'; puts %w[require c]; puts `require d`}
      expect(paths(src)).to eq([])
    end

    it "skips heredocs, including several on one line and squiggly ones" do
      src = <<~RUBY
        a = <<~ONE + <<-TWO
          require "one"
        ONE
          require "two"
          TWO
        b = <<'RAW'
        require "raw"
        RAW
        c = <<"Q".strip
        require "q"
        Q
        require "after"
      RUBY
      expect(scan(src)).to eq([{ kind: :require, path: "after", line: 12 }])
    end

    it "does not take << (shift) for a heredoc" do
      expect(paths(%{list << item\nrequire "a"\nx = 1 <<2\nrequire "b"})).to eq([[:require, "a"], [:require, "b"]])
    end

    it "skips =begin/=end" do
      src = "=begin\nrequire 'a'\n=end\nrequire 'b'\n"
      expect(scan(src)).to eq([{ kind: :require, path: "b", line: 4 }])
    end

    it "stops at __END__" do
      expect(paths("require 'a'\n__END__\nrequire 'b'\n")).to eq([[:require, "a"]])
    end

    it "skips regexps, including ones with quotes and slashes in a class" do
      src = <<~'RUBY'
        x =~ /require "a"/
        y = %r{require 'b'}
        z = str.split(/[\/"]/)
        if /"/.match?(s) then require "c" end
      RUBY
      expect(paths(src)).to eq([[:require, "c"]])
    end

    it "tells division from a regexp" do
      expect(paths(%{a = b / 2; c = d / 3\nrequire "x"})).to eq([[:require, "x"]])
    end

    it "skips character literals" do
      expect(paths(%{c = ?"\nrequire "a"\nd = ?'\n})).to eq([[:require, "a"]])
    end

    it "keeps the ternary operator working" do
      expect(paths(%{x = a ? "b" : "c"\nrequire "d"})).to eq([[:require, "d"]])
    end

    it "skips method calls on a receiver, definitions, symbols and labels" do
      src = <<~RUBY
        Kernel.require "a"
        obj&.load("b")
        YAML.load "c"
        def require(x) = x
        def self.load(x) = x
        sym = :require
        opts = { require: "d", load: true }
        required?("e")
        my_require "f"
        Foo::require "g"
      RUBY
      expect(paths(src)).to eq([])
    end

    it "handles symbols with quotes" do
      expect(paths(%{a = :"x'y"\nrequire "b"})).to eq([[:require, "b"]])
    end

    it "handles non-ASCII text" do
      src = "# café ☕ 日本語\nputs \"naïve\"\nrequire \"bibliothèque\"\n"
      expect(scan(src)).to eq([{ kind: :require, path: "bibliothèque", line: 3 }])
    end

    it "handles CRLF line endings" do
      expect(scan("x = 1\r\nrequire 'a'\r\n")).to eq([{ kind: :require, path: "a", line: 2 }])
    end
  end
end
