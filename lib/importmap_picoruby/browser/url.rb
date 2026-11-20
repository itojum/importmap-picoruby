module ImportmapPicoRuby
  class Browser
    # URL handling for the pure-Ruby part, by the browser's URL.
    module Url
      def self.join(base, ref)
        href = JS.global[:URL].new(ref, base)[:href].to_s
        i = href.index("#")
        i ? href.byteslice(0, i) : href
      end

      def self.split(url)
        u = JS.global[:URL].new(url)
        [u[:origin].to_s, u[:host].to_s, u[:pathname].to_s]
      end
    end
  end
end
