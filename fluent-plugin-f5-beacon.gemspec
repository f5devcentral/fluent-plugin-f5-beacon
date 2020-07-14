# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name          = "fluent-plugin-f5-beacon"
  s.version       = '0.0.1'
  s.authors       = ["Matt Davey"]
  s.email         = ["m.davey@f5.com"]
  s.description   = %q{F5 Beacon output plugin for Fluentd}
  s.summary       = %q{A buffered output plugin for Fluentd and F5 Beacon}
  s.homepage      = "https://github.com/f5devcentral/fluent-plugin-f5-beacon"
  s.license       = "Apache-2.0"

  s.files         = `git ls-files`.split($/)
  s.executables   = s.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]

  s.add_runtime_dependency "fluentd", [">= 1.0", "< 2"]
  s.add_runtime_dependency "influxdb", [">= 0.8.0", "< 1"]

  s.add_development_dependency "rake", '~> 13'
  s.add_development_dependency "pry", '~> 0'
  s.add_development_dependency "test-unit", '~> 3'
end
