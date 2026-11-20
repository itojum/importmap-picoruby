module PicoRubyImportmap
  # Follows requires from the apps' scripts and decides what to fetch. It
  # does no I/O itself: #run yields batches of URLs to fetch (in parallel)
  # and expects a Hash of URL => source (String) or nil (not found).
  class Crawler
    class Node
      attr_reader :url, :tree, :libdir, :refs

      def initialize(url, tree, libdir, refs)
        @url = url
        @tree = tree
        @libdir = libdir
        @refs = refs
      end
    end

    attr_reader :sources, :nodes, :stubs, :errors, :edges, :missing

    # map: ImportMap; url: URL handling (see above);
    # builtins: names require already knows ($LOADED_FEATURES)
    def initialize(map, layout, url, builtins)
      @map = map
      @layout = layout
      @url = url
      @builtins = builtins
      @sources = {}     # URL => source
      @missing = {}     # URL => true
      @nodes = {}       # "tree URL" => Node
      @stubs = {}       # VFS path => source
      @notes = {}       # warning message => locations
      @errors = []
      @edges = []       # [from URL, to URL]
      @requests = []
      @uses_require_relative = false
    end

    def uses_require_relative?
      @uses_require_relative
    end

    # One line per problem; the files that hit it are listed together.
    def warnings
      out = []
      @notes.each do |message, locations|
        if locations.empty?
          out << message
        else
          shown = locations[0, 3].join(", ")
          shown += " and #{locations.size - 3} more" if locations.size > 3
          out << "#{message} (from #{shown})"
        end
      end
      out
    end

    # An app script. source is nil for <script src>, which is fetched.
    def add_app(url, source = nil)
      @sources[url] = source if source
      @requests << { candidates: [url], tree: :app, libdir: nil, stub: nil, from: nil, label: url, root: true }
    end

    def add_preload(pattern)
      if Glob.glob?(pattern)
        matched = @map.names.select { |n| Glob.match?(pattern, n) }
        note("preload #{pattern.inspect} matched no import map name (globs match import map names only)", nil) if matched.empty?
        matched.each { |n| add_request(:require, n, nil, nil, "preload #{pattern.inspect}") }
      else
        add_request(:require, pattern, nil, nil, "preload #{pattern.inspect}")
      end
    end

    def note(message, location)
      locations = (@notes[message] ||= [])
      locations << location if location && !locations.include?(location)
    end

    def run
      loop do
        waiting = []
        # resolving a request may add requests (the requires of its file)
        until @requests.empty?
          batch = @requests
          @requests = []
          batch.each { |r| waiting << r if advance(r) == :wait }
        end
        @requests = waiting
        wanted = []
        waiting.each do |r|
          u = r[:candidates][r[:index]]
          wanted << u unless wanted.include?(u)
        end
        break if wanted.empty?
        results = yield(wanted) || {}
        wanted.each do |u|
          src = results[u]
          if src.nil?
            @missing[u] = true
          else
            @sources[u] = src
          end
        end
      end
      self
    end

    # Files to write: [[VFS path, source], ...] (stubs included)
    def files
      out = []
      seen = {}
      @nodes.each_value do |node|
        next if node.url.include?("#") # an inline <script>
        p = @layout.path(node.tree, node.url)
        next if seen[p]
        seen[p] = true
        out << [p, @sources[node.url]]
      end
      @stubs.each { |p, s| out << [p, s] unless seen[p] }
      out
    end

    # Cycles among the fetched files, each as [url, url, ..., url]
    def cycles
      graph = {}
      @edges.each do |a, b|
        graph[a] ||= []
        graph[a] << b unless graph[a].include?(b)
      end
      state = {}
      found = []
      keys = {}
      visit = lambda do |u, stack|
        state[u] = :active
        stack.push(u)
        (graph[u] || []).each do |v|
          if state[v] == :active
            cyc = stack[stack.index(v), stack.size] + [v]
            key = cyc[0, cyc.size - 1].sort.join(" ")
            unless keys[key]
              keys[key] = true
              found << cyc
            end
          elsif state[v].nil?
            visit.call(v, stack)
          end
        end
        stack.pop
        state[u] = :done
      end
      graph.keys.each { |u| visit.call(u, []) if state[u].nil? }
      found
    end

    private

    # => the resolved URL, :wait (needs a fetch), or nil (gave up)
    def advance(r)
      r[:index] ||= 0
      while r[:index] < r[:candidates].size
        url = r[:candidates][r[:index]]
        if @sources.key?(url)
          resolved(r, url)
          return url
        end
        return :wait unless @missing[url]
        r[:index] += 1
      end
      if r[:root]
        @errors << "cannot fetch #{r[:label]}"
      else
        tried = r[:candidates].join(", ")
        note("#{r[:label]}: not found at #{tried}; it is left to PicoRuby's require at run time", r[:location])
      end
      nil
    end

    def resolved(r, url)
      @edges << [r[:from], url] if r[:from]
      @stubs[@layout.stub_path(r[:stub])] = @layout.stub_source(@layout.path(:lib, url)) if r[:stub]
      key = "#{r[:tree]} #{url}"
      return if @nodes.key?(key)
      refs = Scanner.scan(@sources[url])
      node = Node.new(url, r[:tree], r[:libdir], refs)
      @nodes[key] = node
      refs.each do |ref|
        @uses_require_relative = true if ref[:kind] == :require_relative
        next if ref[:path].nil?
        add_request(ref[:kind], ref[:path], node, ref[:line], nil)
      end
    end

    def add_request(kind, spec, from, line, label)
      location = from ? "#{from.url}:#{line}" : nil
      label ||= "#{kind} #{spec.inspect}"
      r = begin
            resolve(kind, spec, from)
          rescue
            :unresolved # a name that is no valid URL path
          end
      return if r.nil?
      if r == :unresolved
        note("#{label}: no import map entry or load path matches; it is left to PicoRuby's require at run time", location)
        return
      end
      r[:from] = from ? from.url : nil
      r[:label] = label
      r[:location] = location
      @requests << r
    end

    def with_rb(spec)
      spec.end_with?(".rb") ? spec : spec + ".rb"
    end

    # => request Hash, nil (nothing to fetch), or :unresolved
    def resolve(kind, spec, from)
      return nil if spec.empty? || spec.start_with?("/")
      return nil if spec.end_with?(".mrb")
      tree = from ? from.tree : :app
      libdir = from ? from.libdir : nil
      if kind == :require_relative
        return nil unless from
        return { candidates: [@url.join(from.url, with_rb(spec))], tree: tree, libdir: libdir, stub: nil }
      end
      name = spec
      if spec.start_with?("./") || spec.start_with?("../")
        file = kind == :load ? spec : with_rb(spec)
        return { candidates: [@url.join(@layout.page_url, file)], tree: :app, libdir: nil, stub: nil }
      end
      bare = name.end_with?(".rb") ? name.byteslice(0, name.bytesize - 3) : name
      return nil if @builtins.include?(bare)
      hit = @map.lookup(bare)
      if hit
        url, key = hit
        libdir = key.end_with?("/") ? nil : [package_libdir(url, key), key.split("/")[0]]
        return { candidates: [url], tree: :lib, libdir: libdir, stub: bare }
      end
      # A library's require of its own files ("webxr/core" from webxr) is
      # looked up in its lib directory, as a gem's lib is on $LOAD_PATH.
      if from && from.tree == :lib && from.libdir && bare.start_with?(from.libdir[1] + "/")
        return { candidates: [from.libdir[0] + bare + ".rb"], tree: :lib, libdir: from.libdir, stub: bare }
      end
      file = kind == :load ? name : bare + ".rb"
      cands = @map.load_paths.map { |lp| @url.join(lp, file) }
      return :unresolved if cands.empty?
      { candidates: cands, tree: :app, libdir: nil, stub: nil }
    end

    # For "picodx" => ".../lib/picodx.rb" the directory ".../lib/", from
    # which the library's own `require "picodx/sprite"` is resolved.
    def package_libdir(url, name)
      dir = @url.join(url, ".")
      depth = name.split("/").size - 1
      while depth > 0
        nd = @url.join(dir, "..")
        break if nd == dir
        dir = nd
        depth -= 1
      end
      dir
    end
  end
end
