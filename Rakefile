# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/extensiontask"

RSpec::Core::RakeTask.new(:spec)

Rake::ExtensionTask.new("ruby_units_ext") do |ext|
  ext.lib_dir = "lib/ruby_units"
  ext.ext_dir = "ext/ruby_units"
end

task default: :spec
task spec: :compile
