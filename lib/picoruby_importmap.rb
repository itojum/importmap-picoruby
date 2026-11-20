# The part of the loader with no browser dependency: the static scan of
# `require` and name resolution. It runs on PicoRuby (mruby) and on CRuby,
# where it is tested. It sticks to the core of mruby: no Regexp, no Struct,
# no Set, and strings are read by byte.
#
# URL handling is passed in as an object with two methods:
#   join(base, ref)  => the absolute URL of ref against base, without its fragment
#   split(url)       => [origin, host, path]  ("https://h:1", "h:1", "/a/b.rb")
# In the browser it is PicoRubyImportmap::Browser::Url, backed by the browser's URL.

module PicoRubyImportmap
  VERSION = "0.1.0"
  JSDELIVR = "https://cdn.jsdelivr.net/"
  LOG_PREFIX = "[picoruby-importmap] "
end

require_relative "picoruby_importmap/glob"
require_relative "picoruby_importmap/npm"
require_relative "picoruby_importmap/pinned"
require_relative "picoruby_importmap/scanner"
require_relative "picoruby_importmap/import_map"
require_relative "picoruby_importmap/layout"
require_relative "picoruby_importmap/crawler"
require_relative "picoruby_importmap/integrity"
