# frozen_string_literal: true

# Benchmark for measuring gem loading time
require "benchmark"

puts "Ruby Units Loading Time Benchmark"
puts "=" * 50

# Test loading without new parser
loading_time_legacy = Benchmark.measure do
  # Force a fresh load by removing all RubyUnits constants
  Object.send(:remove_const, :RubyUnits) if defined?(RubyUnits)
  $LOADED_FEATURES.reject! { |f| f.include?("ruby-units") || f.include?("ruby_units") }
  
  require_relative "../../lib/ruby-units"
end.real

puts "Legacy loading time: #{(loading_time_legacy * 1000).round(1)}ms"

# Reset everything
Object.send(:remove_const, :RubyUnits) if defined?(RubyUnits)
$LOADED_FEATURES.reject! { |f| f.include?("ruby-units") || f.include?("ruby_units") }

# Test loading with new parser enabled
loading_time_with_parser = Benchmark.measure do
  require_relative "../../lib/ruby-units"
  
  # Enable the new parser to load its classes
  RubyUnits.configure do |config|
    config.use_new_parser = true
  end
  
  # Trigger parser loading
  RubyUnits::Unit.new("1 meter")
end.real

puts "With new parser: #{(loading_time_with_parser * 1000).round(1)}ms"

# Calculate overhead
overhead = loading_time_with_parser - loading_time_legacy
puts "Parser loading overhead: #{(overhead * 1000).round(1)}ms"

# Test parsing performance difference after loading
puts "\nParsing Performance After Loading:"
puts "-" * 35

test_expressions = [
  "5 meters",
  "100 km/h", 
  "9.8 kg*m/s^2",
  "37 degC",
  "1 atm"
]

# Test legacy parser
RubyUnits.configure { |config| config.use_new_parser = false }
legacy_time = Benchmark.measure do
  1000.times do
    test_expressions.each { |expr| RubyUnits::Unit.new(expr) }
  end
end.real

# Test new parser
RubyUnits.configure { |config| config.use_new_parser = true }
new_time = Benchmark.measure do
  1000.times do
    test_expressions.each { |expr| RubyUnits::Unit.new(expr) }
  end
end.real

puts "Legacy parser (5000 expressions): #{(legacy_time * 1000).round(1)}ms"
puts "New parser (5000 expressions): #{(new_time * 1000).round(1)}ms"
puts "Runtime improvement: #{((legacy_time - new_time) / legacy_time * 100).round(1)}%"

puts "\nSummary:"
puts "- Loading overhead: #{(overhead * 1000).round(1)}ms"
puts "- Runtime speedup: #{(legacy_time / new_time).round(1)}x"
puts "- Net benefit starts after: #{((overhead / (legacy_time - new_time)) * test_expressions.length).round(0)} expressions"