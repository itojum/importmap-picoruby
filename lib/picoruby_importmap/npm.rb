module PicoRubyImportmap
  module Npm
    # "npm:picodx@1.2.0/lib/x.rb" => ["https://cdn.jsdelivr.net/npm/picodx@1.2.0/", "lib/x.rb"]
    # The path is "" when the specifier names the package alone.
    def self.split(spec)
      raise ArgumentError, "not an npm: specifier: #{spec}" unless spec.start_with?("npm:")
      rest = spec.byteslice(4, spec.bytesize - 4)
      rest = rest.byteslice(1, rest.bytesize - 1) while rest.start_with?("/")
      start = 0
      if rest.start_with?("@")
        s = rest.index("/")
        raise ArgumentError, "invalid npm: specifier: #{spec}" unless s
        start = s + 1
      end
      slash = rest.index("/", start)
      pkg = slash ? rest.byteslice(0, slash) : rest
      path = slash ? rest.byteslice(slash + 1, rest.bytesize - slash - 1) : ""
      raise ArgumentError, "invalid npm: specifier: #{spec}" if pkg.empty? || pkg.end_with?("@")
      [JSDELIVR + "npm/" + pkg + "/", path]
    end

    # The Ruby entry file of a package from its package.json, or nil.
    def self.entry(package_json)
      return nil unless package_json.is_a?(Hash)
      pr = package_json["picoruby"]
      file = if pr.is_a?(String)
               pr
             elsif pr.is_a?(Hash) && pr["main"].is_a?(String)
               pr["main"]
             elsif package_json["main"].is_a?(String) && package_json["main"].end_with?(".rb")
               package_json["main"]
             end
      return nil if file.nil? || file.empty?
      file = file.byteslice(2, file.bytesize - 2) while file.start_with?("./")
      file
    end
  end
end
