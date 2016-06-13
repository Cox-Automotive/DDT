# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'cf_ddt/version'

Gem::Specification.new do |spec|
  spec.name          = "cf_ddt"
  spec.version       = CfDdt::VERSION
  spec.authors       = ['jason.cornell', 'jd.calder', 'daniel.garcia']
  spec.email         = ['jason.cornell@coxautoinc.com', 'jd.calder@coxautoinc.com', 'daniel.garcia@coxautoinc.com']
  spec.summary       = %q{Cloudforms Developement and Deployment Tool Kit.}
  spec.description   = %q{Cloudforms development and deployment tool kit for continous integration and continuous delivery.}
  spec.homepage      = "https://bitbucket.org/coxauto/cai-cloudforms-v3-production/src/a88113ce0c26?at=dev-one-clone"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib', 'config']

  spec.add_dependency 'json'
  spec.add_dependency 'git'
  spec.add_dependency 'highline'
  spec.add_dependency 'faraday'
  spec.add_dependency 'faraday_middleware'

  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rake'
end
