# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'redmine_api/version'

Gem::Specification.new do |spec|
  spec.name          = "redmine_api"
  spec.version       = RedmineApi::VERSION
  spec.authors       = ["Taiyu Fujii"]
  spec.email         = ["tf.900913@gmail.com"]
  spec.summary       = %q{API for Redmine.}
  spec.description   = %q{API for Redmine like Rails's model.}
  spec.homepage      = "https://github.com/taiyuf/ruby-redmine_api"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "hashie"
  spec.add_development_dependency "activemodel"
  spec.add_development_dependency 'webmock'
end
