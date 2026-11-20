# picoruby-importmap -- Import maps and `require` for PicoRuby.wasm
#
# An unofficial loader. It reads <script type="text/ruby-importmap"> and
# <script type="text/ruby-app"> from the page, fetches every file that the
# apps can `require`, writes them into the PicoRuby.wasm virtual file system
# and starts each app as a task. The apps then use PicoRuby's own `require`.
#
# MIT License. https://github.com/itojum/importmap-picoruby

require_relative "picoruby_importmap"
require "js"
require_relative "picoruby_importmap/browser/url"
require_relative "picoruby_importmap/browser"

PicoRubyImportmap::Browser.new.run
