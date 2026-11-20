# picoruby-importmap

Import maps and `require` for PicoRuby.wasm

> **This is an unofficial tool.** It is not part of the PicoRuby / PicoRuby.wasm project.
> Tested with PicoRuby.wasm 4.0.5.

PicoRuby.wasm starts with an empty virtual file system (VFS), so `require "x"` raises
`LoadError` in the browser. picoruby-importmap works like the HTML import map: it maps library
names to URLs, fetches every file your app can `require` before the app runs, and writes them
into the VFS. PicoRuby's own `require` then loads them. There is no build step; everything
happens when the page loads.

## Usage

```html
<script type="text/ruby-importmap">
{
  "imports": {
    "picodx": "npm:picodx@2.1.2",
    "mylib": "https://cdn.jsdelivr.net/gh/you/mylib@abc1234/lib/mylib.rb"
  },
  "integrity": {
    "https://cdn.jsdelivr.net/gh/you/mylib@abc1234/lib/mylib.rb": "sha384-..."
  },
  "loadPaths": ["./src/"],
  "preload": ["plugins/*"]
}
</script>
<script type="text/ruby" src="https://cdn.jsdelivr.net/npm/picoruby-importmap@0/loader.rb"></script>
<script type="text/ruby-app" src="src/main.rb"></script>
<script src="https://cdn.jsdelivr.net/npm/@picoruby/wasm-wasi@4.0.5/dist/init.iife.js"></script>
```

- `text/ruby-importmap`: the import map (see below).
- `text/ruby` with `loader.rb`: the loader. It runs as a PicoRuby.wasm task.
- `text/ruby-app`: your app's scripts, with `src` or inline. `init.iife.js` does not run
  `text/ruby-app`; the loader starts them as tasks, in document order, once every file is in place.

Write your app as plain Ruby. The same HTML works in development and in production.

```ruby
# src/main.rb
require "picodx"        # from the import map
require "mylib"
require "./lib/enemy"   # relative to the page's directory (see below)

def start_scene
  require "scene"       # searched in loadPaths; requires inside methods are fetched up front too
  Scene.new
end
```

Working examples: [examples/basic](examples/basic/index.html) (picodx and an app split into
files) and [examples/webxr](examples/webxr/index.html) (checks where webxr-ruby's files are placed).

## The import map

`<script type="text/ruby-importmap">` holds JSON, inline or from a `src` attribute. Several maps
are merged; for the same name or URL, the first one wins. Relative URLs are resolved against
the page URL (`document.baseURI`).

### `imports`: name → URL

| Entry | Meaning |
|---|---|
| `"picodx": "npm:picodx@2.1.2"` | An npm package. The entry file comes from its package.json |
| `"util": "npm:util-rb@1.0.0/lib/util.rb"` | A file in an npm package |
| `"mylib": "https://.../mylib.rb"` | Any URL (relative URLs too) |
| `"ui/": "./vendor/ui/"` | A prefix, as in HTML import maps: `require "ui/button"` → `./vendor/ui/button.rb` |

`npm:<name>@<version>[/<path>]` expands to `https://cdn.jsdelivr.net/npm/<name>@<version>/<path>`
(`@scope/name` works too). Without a path, the Ruby entry file is taken from package.json:

1. `picoruby` (a string, or `{ "main": "..." }`)
2. `main`, only if it ends in `.rb`

If neither is there, the loader reports an error; give the path in the specifier instead.

A library's own `require "<name>/..."` (such as `require "picodx/sprite"` inside `picodx`) is
looked up in the directory of its entry file, as if the gem's `lib` were on `$LOAD_PATH`.

### `integrity`: URL → hash

Same format as in HTML import maps: `"sha384-..."`. With several space-separated values, the
strongest algorithm is used. sha256, sha384 and sha512 are supported, and keys may be written as
`npm:` specifiers. A file whose hash does not match is not used and an error is reported (its
`require` raises `LoadError` at run time).

To compute a hash:

```bash
curl -s <URL> | openssl dgst -sha384 -binary | openssl base64 -A
```

### `loadPaths`: directories to search

URLs relative to the page. A `require "x"` without `./` whose name is not in the import map is
looked up as `<loadPath>/x.rb`, in order.

### `preload`: files to fetch in advance

For requires the loader cannot follow statically, such as `require name` or
`require "plugins/#{name}"`, list the names to fetch. They are resolved like `require`.

Globs (`*`, `?`, `**`) are matched against **import map names**. HTTP cannot list a directory, so
a glob cannot match files on a server. To use `"plugins/*"`, put `"plugins/a"`, `"plugins/b"`,
... in the import map.

## How requires are resolved

The loader scans each script and collects calls to `require`, `require_relative` and `load` —
at the top level and also inside methods, blocks and conditionals. Strings, comments, heredocs,
`=begin`/`=end` and everything after `__END__` are skipped. Calls whose argument is not a string
literal are not followed (use `preload`).

| Call | Where it is looked up |
|---|---|
| `require "./x"`, `"../x"` | The page's directory (CRuby's working directory) |
| `require "x"` | The import map, then `loadPaths` |
| `require "js"` etc. | Built into PicoRuby (listed in `$LOADED_FEATURES`); not fetched |
| `require_relative "x"` | Relative to the URL of the calling file |
| `load "x.rb"` | Like `require`, without adding `.rb` |

A file that cannot be fetched is only a warning; the app still runs, and `require` raises
`LoadError` at run time. Files that do not depend on each other are fetched in parallel, each
URL only once, and circular requires are detected.

## Layout in the VFS

Files keep their positions relative to each other as on the server, so `require_relative`
will resolve unchanged once PicoRuby supports it.

| Kind | Path |
|---|---|
| Library | `/lib/<host>/<path>` (e.g. `/lib/cdn.jsdelivr.net/npm/picodx@2.1.2/lib/picodx.rb`) |
| Library name | `/lib/<name>.rb`, a one-line file that requires the library |
| App file, same origin as the page | `/app/<path>` (e.g. `/app/src/main.rb`) |
| App file, other origin | `/app/<host>/<path>` |

Before starting each app script, the loader puts a short preamble at the start of its first
line that sets `$LOAD_PATH` (`["/lib", <loadPaths>...]`) and the working directory. It stays on
line 1, so line numbers do not change (unless the script starts with `=begin`). `__FILE__` is
the VFS path above.

## Cache

Fetched files are stored with the Cache API (`picoruby-importmap-v1`), keyed by URL + integrity.
Only URLs whose content cannot change are read from the cache afterwards:

- npm on jsDelivr with an exact version (`@2.1.2`; not `@2` or `@latest`)
- GitHub on jsDelivr with a commit (7–40 hex digits) or a version tag
- URLs with an `integrity` value

Everything else (such as your own files during development) is fetched every time.

## Events and errors

Errors go to `console.error`; requires that cannot be fetched and similar problems go to
`console.warn`. These events are dispatched on `document`:

```js
document.addEventListener("picoruby-importmap:ready", (e) => {
  // e.detail: { files: [VFS paths...], apps: number of apps started, warnings: [...], errors: number of errors }
});
document.addEventListener("picoruby-importmap:error", (e) => {
  // e.detail: { message, url? }
});
```

If any loaded file calls `require_relative` and the runtime does not define it, a warning is
shown once at startup.

## Development

```bash
bundle install
```

The source is split under `lib/`. `loader.rb`, the single file users load, is generated from it
(and is not committed):

```bash
bundle exec rake build
```

- `lib/loader.rb`: the entry point of the generated file
- `lib/picoruby_importmap.rb` and `lib/picoruby_importmap/*.rb`: the part with no browser
  dependency (the scan, name resolution). It avoids Regexp, Struct and the like so that it runs
  on mruby.
- `lib/picoruby_importmap/browser.rb` and `browser/`: fetching, the VFS, tasks, the cache

The build replaces each `require_relative` in `lib/loader.rb` (and the files it pulls in) with
the file's contents, since PicoRuby.wasm starts with an empty file system.

Tests run on CRuby with RSpec. URL handling is passed in: the loader uses the browser's `URL`,
and the specs use a simple stand-in (`spec/support/simple_url.rb`).

```bash
bundle exec rake spec
```

To try the examples, build `loader.rb`, serve the repository root and open
<http://localhost:8000/examples/basic/> or <http://localhost:8000/examples/webxr/>:

```bash
bundle exec ruby -run -e httpd . -p 8000
```

## License

MIT
