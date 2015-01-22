# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'lock_and_cache/version'

Gem::Specification.new do |spec|
  spec.name          = "lock_and_cache"
  spec.version       = LockAndCache::VERSION
  spec.authors       = ["Seamus Abshere"]
  spec.email         = ["seamus@abshere.net"]
  spec.summary       = %q{Lock and cache methods.}
  spec.description   = %q{Lock and cache methods, in case things should only be calculated once across processes.}
  spec.homepage      = "https://github.com/seamusabshere/lock_and_cache"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency 'activerecord'
  spec.add_runtime_dependency 'hash_digest'
  spec.add_runtime_dependency 'with_advisory_lock'

  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'activesupport'
  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'pg'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'redis'
end
