require 'rubygems'
require 'rake'
require './lib/puppet-pssh.rb'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.version = PuppetPSSH::VERSION
  gem.name = "puppet-pssh"
  gem.homepage = "http://github.com/rubiojr/puppet-pssh"
  gem.license = "MIT"
  gem.summary = %Q{Puppet parallel-ssh integration}
  gem.description = %Q{Puppet parallel-ssh integration}
  gem.email = "rubiojr@frameos.org"
  gem.authors = ["Sergio Rubio"]
  # Include your dependencies below. Runtime dependencies are required when using your gem,
  # and development dependencies are only needed for development (ie running rake tasks, tests, etc)
  gem.add_runtime_dependency 'colored'
  gem.add_runtime_dependency 'excon'
  gem.add_runtime_dependency 'net-dns'
  gem.add_runtime_dependency 'json'
  gem.add_runtime_dependency 'clamp'
  gem.add_development_dependency 'rspec', '> 1.2.3'
  gem.add_development_dependency 'jeweler'
end
Jeweler::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

task :default => :build
