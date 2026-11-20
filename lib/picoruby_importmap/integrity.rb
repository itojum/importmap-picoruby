module PicoRubyImportmap
  module Integrity
    ALGORITHMS = { "sha512" => "SHA-512", "sha384" => "SHA-384", "sha256" => "SHA-256" }
    STRENGTH = ["sha512", "sha384", "sha256"]

    # "sha256-a sha384-b" => ["SHA-384", ["b"]] (the strongest algorithm)
    def self.parse(value)
      by_alg = {}
      value.split(" ").each do |tok|
        tok = tok.strip
        d = tok.index("-")
        next unless d
        alg = tok.byteslice(0, d).downcase
        next unless ALGORITHMS.key?(alg)
        digest = tok.byteslice(d + 1, tok.bytesize - d - 1)
        q = digest.index("?")
        digest = digest.byteslice(0, q) if q
        (by_alg[alg] ||= []) << digest
      end
      STRENGTH.each { |a| return [ALGORITHMS[a], by_alg[a]] if by_alg[a] }
      nil
    end

    # The Cache API key for a URL and its integrity value.
    def self.cache_key(url, integrity)
      return url if integrity.nil? || integrity.empty?
      sep = url.include?("?") ? "&" : "?"
      url + sep + "picoruby-importmap-integrity=" + integrity.split(" ").join("_")
    end
  end
end
