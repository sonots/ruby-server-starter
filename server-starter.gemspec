# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'server/starter/version'

Gem::Specification.new do |s|
  s.name        = "server-starter"
  s.version     = Server::Starter::VERSION
  s.authors     = ["Naotoshi Seo"]
  s.email       = ["sonots@gmail.com"]
  s.homepage    = "https://github.com/sonots/ruby-server-starter"
  s.summary     = "a superdaemon for hot-deploying server programs (ruby port of p5-Server-Starter)"
  s.description = s.summary
  s.licenses    = ["MIT"]

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency "rake"
end
