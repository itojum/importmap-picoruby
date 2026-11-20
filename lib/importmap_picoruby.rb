# The part of the loader with no browser dependency: the static scan of
# `require` and name resolution. It runs on PicoRuby (mruby) and on CRuby,
# where it is tested. It sticks to the core of mruby: no Regexp, no Struct,
# no Set, and strings are read by byte.
#
# URL handling is passed in as an object with two methods:
#   join(base, ref)  => the absolute URL of ref against base, without its fragment
#   split(url)       => [origin, host, path]  ("https://h:1", "h:1", "/a/b.rb")
# In the browser it is ImportmapPicoRuby::Browser::Url, backed by the browser's URL.

module ImportmapPicoRuby
  VERSION = "0.1.0"
  JSDELIVR = "https://cdn.jsdelivr.net/"
  LOG_PREFIX = "[importmap-picoruby] "
end

require_relative "importmap_picoruby/glob"
require_relative "importmap_picoruby/npm"
require_relative "importmap_picoruby/pinned"
require_relative "importmap_picoruby/scanner"
require_relative "importmap_picoruby/import_map"
require_relative "importmap_picoruby/layout"
require_relative "importmap_picoruby/crawler"
require_relative "importmap_picoruby/integrity"
