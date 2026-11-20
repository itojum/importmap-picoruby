module ImportmapPicoRuby
  # Where files go in the virtual file system. Positions in a URL tree are
  # kept, so a later `require_relative` resolves the same way it does on the
  # server:
  #   libraries  /lib/<host>/<path>     plus /lib/<name>.rb, which requires it
  #   app files  /app/<path>            (same origin as the page)
  #              /app/<host>/<path>     (another origin)
  class Layout
    attr_reader :page_url

    # page_url: without a fragment; url: URL handling (see above)
    def initialize(page_url, url)
      @page_url = page_url
      @url = url
      @origin = url.split(page_url)[0]
    end

    def path(tree, url)
      origin, host, p = @url.split(url)
      if tree == :app && origin == @origin
        "/app" + p
      else
        "/#{tree}/" + host + p
      end
    end

    # The working directory: the page's directory in /app.
    def cwd
      dir_path(path(:app, @url.join(@page_url, ".")))
    end

    def dir_path(p)
      p.end_with?("/") && p.bytesize > 1 ? p.byteslice(0, p.bytesize - 1) : p
    end

    def stub_path(name)
      "/lib/" + name + ".rb"
    end

    def stub_source(target)
      target = target.byteslice(0, target.bytesize - 3) if target.end_with?(".rb")
      "# importmap-picoruby\nrequire #{target.inspect}\n"
    end

    # $LOAD_PATH for the apps.
    def load_path(load_path_urls, legacy_dot)
      lp = ["/lib"]
      load_path_urls.each { |u| lp << dir_path(path(:app, u)) }
      lp << cwd if legacy_dot && !lp.include?(cwd)
      lp
    end

    # Put in front of each app script. It stays on line 1, so line numbers
    # are unchanged (unless the script starts with =begin).
    def preamble(load_path)
      "($LOAD_PATH ||= []).replace(#{load_path.inspect}); (Dir.chdir(#{cwd.inspect}) rescue nil);"
    end

    def with_preamble(source, load_path)
      pre = preamble(load_path)
      source.start_with?("=begin") ? pre + "\n" + source : pre + " " + source
    end
  end
end
