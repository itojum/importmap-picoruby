module PicoRubyImportmap
  # A URL whose content cannot change: an exact npm version or a git commit
  # on jsDelivr. Such URLs are read from the Cache API after the first fetch.
  module Pinned
    def self.pinned?(url)
      return false unless url.start_with?(JSDELIVR)
      rest = url.byteslice(JSDELIVR.bytesize, url.bytesize - JSDELIVR.bytesize)
      if rest.start_with?("npm/")
        segs = rest.byteslice(4, rest.bytesize - 4).split("/")
        pkg = segs[0].to_s.start_with?("@") ? segs[1].to_s : segs[0].to_s
        at = pkg.index("@")
        at ? semver?(pkg.byteslice(at + 1, pkg.bytesize - at - 1)) : false
      elsif rest.start_with?("gh/")
        segs = rest.byteslice(3, rest.bytesize - 3).split("/")
        repo = segs[1].to_s
        at = repo.index("@")
        return false unless at
        ref = repo.byteslice(at + 1, repo.bytesize - at - 1)
        commit?(ref) || semver?(ref.start_with?("v") ? ref.byteslice(1, ref.bytesize - 1) : ref)
      else
        false
      end
    end

    # 1.2.3, 1.2.3-beta.1, 1.2.3+build
    def self.semver?(v)
      core_end = v.bytesize
      i = 0
      while i < v.bytesize
        b = v.getbyte(i)
        if b == 45 || b == 43
          core_end = i
          break
        end
        i += 1
      end
      core = v.byteslice(0, core_end).split(".", -1)
      return false unless core.size == 3
      core.all? { |n| !n.empty? && digits?(n) }
    end

    def self.commit?(ref)
      return false unless ref.bytesize >= 7 && ref.bytesize <= 40
      i = 0
      while i < ref.bytesize
        b = ref.getbyte(i)
        return false unless (b >= 48 && b <= 57) || (b >= 97 && b <= 102)
        i += 1
      end
      true
    end

    def self.digits?(s)
      i = 0
      while i < s.bytesize
        b = s.getbyte(i)
        return false unless b >= 48 && b <= 57
        i += 1
      end
      true
    end
  end
end
