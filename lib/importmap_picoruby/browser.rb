module ImportmapPicoRuby
  class Browser
    CACHE_NAME = "importmap-picoruby-v1"

    def initialize
      @console = JS.global[:console]
      @errors = 0
    end

    def log_error(message, detail = {})
      @errors += 1
      @console.error(LOG_PREFIX + message)
      dispatch("importmap-picoruby:error", { message: message }.merge(detail))
    end

    def warn(message)
      @console.warn(LOG_PREFIX + message)
    end

    def dispatch(name, detail)
      JS.document.dispatchEvent(JS.global[:CustomEvent].new(name, JS::Bridge.to_js({ detail: detail })))
    rescue => e
      @console.error(LOG_PREFIX + "cannot dispatch #{name}: #{e.message}")
    end

    def run
      page_url = Url.join(JS.document[:baseURI].to_s, "")
      layout = Layout.new(page_url, Url)
      map = read_import_maps(page_url)
      map.errors.each { |m| log_error("import map: " + m) }
      resolve_packages(map)

      builtins = ($LOADED_FEATURES || []).select { |f| !f.start_with?("/") }
      crawler = Crawler.new(map, layout, Url, builtins)
      apps = read_apps(page_url, crawler)
      map.preload.each { |p| crawler.add_preload(p) }
      crawler.run { |urls| fetch_all(urls, map.integrity) }
      crawler.errors.each { |m| log_error(m) }
      crawler.warnings.each { |w| warn(w) }

      if $__require_loading.nil?
        crawler.cycles.each do |c|
          warn("circular require: #{c.join(' -> ')} (this PicoRuby has no guard against circular require)")
        end
      end
      if crawler.uses_require_relative? && !respond_to?(:require_relative, true)
        warn("some files call require_relative, which this PicoRuby does not define yet. " \
             "The files are placed so that it will work once PicoRuby supports it.")
      end

      files = crawler.files
      files.each { |path, src| write_file(path, src) }
      mkdir_p(layout.cwd)
      legacy_dot = !respond_to?(:__require_load_paths, true)
      load_path = layout.load_path(map.load_paths, legacy_dot)
      ($LOAD_PATH ||= []).replace(load_path)
      begin
        Dir.chdir(layout.cwd)
      rescue => e
        warn("cannot change the working directory: #{e.message}")
      end

      started = 0
      apps.each do |app|
        src = app[:inline] || crawler.sources[app[:url]]
        next if src.nil? # already reported by the crawler
        filename = app[:inline] ? "#{layout.cwd}/(ruby-app #{app[:index]}).rb" : layout.path(:app, app[:url])
        if start_task(layout.with_preamble(src, load_path), filename)
          started += 1
        else
          log_error("cannot start #{filename}: a syntax error?", { url: app[:url].to_s })
        end
      end
      dispatch("importmap-picoruby:ready", {
        files: files.map { |f| f[0] },
        apps: started,
        warnings: crawler.warnings,
        errors: @errors,
      })
    rescue => e
      log_error("#{e.class}: #{e.message}")
    end

    def read_import_maps(page_url)
      map = ImportMap.new(page_url, Url)
      JS.document.querySelectorAll('script[type="text/ruby-importmap"]').to_a.each do |el|
        src = el.getAttribute("src")
        text = nil
        label = "inline import map"
        if src && !src.to_s.empty?
          label = Url.join(page_url, src.to_s)
          text = fetch_text(label)
          if text.nil?
            log_error("cannot fetch the import map #{label}", { url: label })
            next
          end
        else
          text = el[:textContent].to_s
        end
        begin
          map.add(JSON.parse(text))
        rescue => e
          log_error("#{label}: invalid JSON (#{e.message})")
        end
      end
      map
    end

    def read_apps(page_url, crawler)
      apps = []
      JS.document.querySelectorAll('script[type="text/ruby-app"]').to_a.each_with_index do |el, i|
        src = el.getAttribute("src")
        if src && !src.to_s.empty?
          url = Url.join(page_url, src.to_s)
          crawler.add_app(url)
          apps << { url: url, inline: nil, index: i + 1 }
        else
          url = page_url + "#ruby-app-#{i + 1}"
          code = el[:textContent].to_s
          crawler.add_app(url, code)
          apps << { url: url, inline: code, index: i + 1 }
        end
      end
      apps
    end

    # npm:<pkg>@<ver> without a path: read the entry from package.json.
    def resolve_packages(map)
      bases = map.packages
      return if bases.empty?
      jsons = fetch_all(bases.map { |b| b + "package.json" }, {})
      bases.each do |base|
        text = jsons[base + "package.json"]
        entry = nil
        begin
          entry = Npm.entry(JSON.parse(text)) if text
        rescue => e
          log_error("#{base}package.json: invalid JSON (#{e.message})")
        end
        if entry
          map.set_package_entry(base, base + entry)
        else
          log_error("#{base}package.json has no Ruby entry: set \"picoruby\" (or a \"main\" ending in .rb), " \
                    "or name the file in the import map (npm:<name>@<version>/<path>)", { url: base })
        end
      end
    end

    def fetch_text(url)
      r = fetch_all([url], {})
      r[url]
    end

    # Fetches the URLs in parallel. => { url => String or nil }
    def fetch_all(urls, integrity)
      out = {}
      cache = open_cache
      todo = []
      urls.each do |url|
        integ = integrity[url]
        if cache && (integ || Pinned.pinned?(url))
          text = cached(cache, url, integ)
          if text
            out[url] = text
            next
          end
        end
        todo << url
      end
      return out if todo.empty?
      fetch = JS.global[:fetch]
      promises = todo.map { |u| fetch.call(u) }
      settled = JS.global[:Promise].allSettled(JS::Bridge.to_js(promises)).await
      todo.each_with_index do |url, i|
        item = settled[i]
        if item[:status].to_s != "fulfilled"
          out[url] = nil
          next
        end
        res = item[:value]
        unless res[:ok]
          out[url] = nil
          next
        end
        buf = res.arrayBuffer.await
        integ = integrity[url]
        if integ && !verify(buf, integ, url)
          out[url] = nil
          next
        end
        out[url] = JS.global[:TextDecoder].new.decode(buf).to_s
        if cache && (integ || Pinned.pinned?(url))
          begin
            cache.put(Integrity.cache_key(url, integ), JS.global[:Response].new(buf)).await
          rescue => e
            warn("cannot cache #{url}: #{e.message}")
          end
        end
      end
      out
    rescue => e
      log_error("fetch failed: #{e.message}")
      out
    end

    def open_cache
      return @cache if @cache_checked
      @cache_checked = true
      caches = JS.global[:caches]
      @cache = caches.nil? ? nil : caches.open(CACHE_NAME).await
    rescue
      @cache = nil
    end

    def cached(cache, url, integ)
      res = cache.match(Integrity.cache_key(url, integ)).await
      return nil if res.nil?
      buf = res.arrayBuffer.await
      return nil if integ && !verify(buf, integ, url, false)
      JS.global[:TextDecoder].new.decode(buf).to_s
    rescue
      nil
    end

    def verify(buf, integ, url, report = true)
      alg_digests = Integrity.parse(integ)
      if alg_digests.nil?
        log_error("integrity for #{url} has no supported hash (sha256, sha384 or sha512)", { url: url }) if report
        return false
      end
      alg, digests = alg_digests
      dig = JS.global[:crypto][:subtle].digest(alg, buf).await
      actual = Base64.encode64(JS.global[:Response].new(dig).to_binary).split("\n").join
      return true if digests.include?(actual)
      if report
        log_error("integrity mismatch for #{url}: expected #{alg.downcase.split('-').join}-#{digests.join(' or ')}, " \
                  "got #{alg.downcase.split('-').join}-#{actual}", { url: url })
      end
      false
    end

    def mkdir_p(dir)
      cur = ""
      dir.split("/").each do |seg|
        next if seg.empty?
        cur += "/" + seg
        Dir.mkdir(cur) unless Dir.exist?(cur)
      end
    end

    def write_file(path, src)
      si = path.rindex("/")
      mkdir_p(path.byteslice(0, si)) if si && si > 0
      File.open(path, "w") { |f| f.write(src) }
    rescue => e
      log_error("cannot write #{path}: #{e.message}")
    end

    # picorb_create_task_with_filename is called from a microtask, outside
    # this task's stack. Called directly from a running Ruby task, the new
    # task's top-level `def`s land on the wrong class (NoMethodError when the
    # app calls them). Promise.prototype.then is taken from the prototype
    # because JS::Promise#then is a Ruby method that takes a block.
    def start_task(code, filename)
      mod = JS.global[:picorubyModule]
      fn = mod[:ccall].bind(mod, "picorb_create_task_with_filename", "number",
                            JS::Bridge.to_js(["string", "string"]), JS::Bridge.to_js([code, filename]))
      promise = JS.global[:Promise].resolve
      JS.global[:Promise][:prototype][:then].bind(promise).call(fn).await.to_i == 0
    end
  end
end
