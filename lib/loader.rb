# importmap-picoruby -- Import maps and `require` for PicoRuby.wasm
#
# An unofficial loader. It reads <script type="text/ruby-importmap"> and
# <script type="text/ruby-app"> from the page, fetches every file that the
# apps can `require`, writes them into the PicoRuby.wasm virtual file system
# and starts each app as a task. The apps then use PicoRuby's own `require`.
#
# MIT License. https://github.com/itojum/importmap-picoruby

require_relative "importmap_picoruby"
require "js"
require_relative "importmap_picoruby/browser/url"
require_relative "importmap_picoruby/browser"

ImportmapPicoRuby::Browser.new.run
