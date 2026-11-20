module ImportmapPicoRuby
  class ImportMap
    attr_reader :imports, :integrity, :load_paths, :preload, :errors

    # page_url: the base for relative URLs; url: URL handling (see above)
    def initialize(page_url, url)
      @page_url = page_url
      @url = url
      @imports = {}     # name => URL (or "npm-package:<base URL>")
      @integrity = {}   # URL => "sha384-..."
      @load_paths = []  # directory URLs, ending with "/"
      @preload = []
      @errors = []
    end

    # Merges one <script type="text/ruby-importmap">. Earlier maps win.
    def add(json)
      unless json.is_a?(Hash)
        @errors << "the import map must be a JSON object"
        return self
      end
      imports = json["imports"] || {}
      if imports.is_a?(Hash)
        imports.each do |name, value|
          next if @imports.key?(name)
          if !value.is_a?(String) || value.empty?
            @errors << "imports[#{name.inspect}] must be a URL string"
            next
          end
          url = resolve(value)
          if url.nil?
            @errors << "imports[#{name.inspect}]: cannot resolve #{value.inspect}"
          elsif name.end_with?("/") && !url.end_with?("/")
            @errors << "imports[#{name.inspect}] ends with \"/\", so its URL must end with \"/\" too"
          else
            @imports[name] = url
          end
        end
      else
        @errors << "\"imports\" must be an object"
      end
      integrity = json["integrity"] || {}
      if integrity.is_a?(Hash)
        integrity.each do |key, value|
          url = resolve(key)
          next if url.nil? || url.start_with?("npm-package:") || @integrity.key?(url)
          if value.is_a?(String)
            @integrity[url] = value
          else
            @errors << "integrity[#{key.inspect}] must be a string"
          end
        end
      else
        @errors << "\"integrity\" must be an object"
      end
      list(json, "loadPaths").each do |lp|
        url = resolve(lp)
        next if url.nil?
        url += "/" unless url.end_with?("/")
        @load_paths << url unless @load_paths.include?(url)
      end
      list(json, "preload").each { |p| @preload << p unless @preload.include?(p) }
      self
    end

    def list(json, key)
      v = json[key]
      return [] if v.nil?
      unless v.is_a?(Array) && v.all? { |x| x.is_a?(String) }
        @errors << "#{key.inspect} must be an array of strings"
        return []
      end
      v
    end

    # npm: specifiers become jsDelivr URLs. A package without a path becomes
    # "npm-package:<package URL>", resolved later from its package.json.
    def resolve(value)
      if value.start_with?("npm:")
        base, path = Npm.split(value)
        path.empty? && !value.end_with?("/") ? "npm-package:" + base : base + path
      else
        @url.join(@page_url, value)
      end
    rescue
      nil
    end

    # Replaces "npm-package:" entries; entries maps base URL => entry path.
    def set_package_entry(base, entry_url)
      @imports.keys.each do |k|
        @imports[k] = entry_url if @imports[k] == "npm-package:" + base
      end
    end

    def packages
      out = []
      @imports.values.each do |v|
        if v.start_with?("npm-package:")
          base = v.byteslice(12, v.bytesize - 12)
          out << base unless out.include?(base)
        end
      end
      out
    end

    # => [url, key] for an exact or prefix ("name/") match, or nil
    def lookup(name)
      bare = name.end_with?(".rb") ? name.byteslice(0, name.bytesize - 3) : name
      url = @imports[bare] || @imports[bare + ".rb"]
      return [url, bare] if url && !url.start_with?("npm-package:")
      best = nil
      @imports.each_key do |key|
        next unless key.end_with?("/") && bare.start_with?(key) && bare.bytesize > key.bytesize
        best = key if best.nil? || key.bytesize > best.bytesize
      end
      return nil unless best
      [@imports[best] + bare.byteslice(best.bytesize, bare.bytesize - best.bytesize) + ".rb", best]
    end

    def names
      @imports.keys.select { |k| !k.end_with?("/") }
    end
  end
end
