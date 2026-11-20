module PicoRubyImportmap
  # `*` and `?` do not cross "/", `**` does.
  module Glob
    def self.glob?(pattern)
      pattern.include?("*") || pattern.include?("?")
    end

    def self.match?(pattern, str)
      m(pattern, 0, str, 0)
    end

    def self.m(pat, pi, str, si)
      while pi < pat.bytesize
        c = pat.getbyte(pi)
        if c == 42 # *
          if pat.getbyte(pi + 1) == 42
            rest = pi + 2
            rest += 1 if pat.getbyte(rest) == 47 && (rest == 2 || pat.getbyte(pi - 1) == 47)
            k = si
            while k <= str.bytesize
              return true if m(pat, rest, str, k)
              k += 1
            end
            return false
          end
          k = si
          while true
            return true if m(pat, pi + 1, str, k)
            break if k >= str.bytesize || str.getbyte(k) == 47
            k += 1
          end
          return false
        elsif c == 63 # ?
          return false if si >= str.bytesize || str.getbyte(si) == 47
        else
          return false if si >= str.bytesize || str.getbyte(si) != c
        end
        pi += 1
        si += 1
      end
      si == str.bytesize
    end
  end
end
