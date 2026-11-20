require "js"
require "picodx"
require "./lib/enemy"   # relative to the page's directory, like CRuby's working directory

def log(msg)
  el = JS.document.getElementById("log")
  el[:textContent] = el[:textContent].to_s + msg + "\n"
  JS.global[:console].log("[example] " + msg)
end

def start_scene
  require "title" # found through loadPaths (./scenes/)
  TitleScene.new
end

log "picodx loaded: #{defined?(PicoDX) ? 'yes' : 'no'}"
log Enemy.new.to_s
log start_scene.to_s
log "main.rb line #{__LINE__} in #{__FILE__}"
