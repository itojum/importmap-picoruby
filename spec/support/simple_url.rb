# A simple stand-in for the browser's URL, given to the loader in tests.
# It covers the http(s) URLs the specs use; it is not a full WHATWG URL.
module SimpleUrl
  def self.join(base, ref)
    ref = ref.split("#", 2)[0] || ""
    return normalize(ref) if ref.match?(%r{\A[a-z][a-z0-9+.-]*:}i)
    origin, _host, path = split(base)
    return normalize(base[/\A[a-z]+:/i] + ref) if ref.start_with?("//")
    return origin + path + (base[/\?[^#]*/] || "") if ref.empty?
    path = ref.start_with?("/") ? ref : path.sub(%r{[^/]*\z}, "") + ref
    origin + remove_dots(path)
  end

  def self.split(url)
    m = url.match(%r{\A([a-z]+://([^/?#]+))([^?#]*)}i) or raise ArgumentError, "invalid URL: #{url}"
    [m[1], m[2], m[3].empty? ? "/" : m[3]]
  end

  def self.normalize(url)
    origin, _host, path = split(url)
    origin + remove_dots(path) + (url[/\?[^#]*/] || "")
  end

  def self.remove_dots(path)
    query = path[/\?.*/] || ""
    path = path.sub(/\?.*/, "")
    out = []
    segs = path.split("/", -1)
    segs.each_with_index do |seg, i|
      last = i == segs.size - 1
      case seg
      when "." then out << "" if last
      when ".." then (out.pop if out.size > 1; out << "" if last)
      else out << seg
      end
    end
    out.join("/").then { |p| p.start_with?("/") ? p : "/" + p } + query
  end
end
