#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'benchmark'
require_relative '../../lib/ruby-units'

# Test expressions covering various complexity levels
TEST_EXPRESSIONS = [
  # Simple units
  "meter", "kg", "s", "ft", "in",
  
  # Units with scalars
  "5 meters", "10 kg", "3.14 seconds",
  
  # Prefixed units
  "kilometer", "mm", "microgram",
  
  # Compound units
  "m/s", "kg*m", "kg/m^3", "m^2", "s^-1",
  
  # Complex expressions
  "kg*m/s^2", "kg*m^2/s^2", "9.8 m/s^2",
  
  # Real world units
  "100 km/h", "37 degC", "1 atm", "60 Hz",
  
  # Special formats
  "50%", "$15.50"
].freeze

def benchmark_parser(use_new_parser, iterations = 1000)
  RubyUnits.configure do |config|
    config.use_new_parser = use_new_parser
    config.compatibility_mode = false
  end
  
  # Warm up
  TEST_EXPRESSIONS.each { |expr| RubyUnits::Unit.new(expr) rescue nil }
  
  # Benchmark
  total_time = Benchmark.measure do
    iterations.times do
      TEST_EXPRESSIONS.each do |expr|
        RubyUnits::Unit.new(expr) rescue nil
      end
    end
  end.real
  
  {
    parser: use_new_parser ? "New" : "Legacy",
    total_time: total_time,
    avg_per_expression: total_time / (iterations * TEST_EXPRESSIONS.length),
    expressions_per_second: (iterations * TEST_EXPRESSIONS.length) / total_time
  }
end

def format_time(seconds)
  if seconds < 0.001
    "#{(seconds * 1_000_000).round(1)}μs"
  elsif seconds < 1
    "#{(seconds * 1000).round(1)}ms"
  else
    "#{seconds.round(3)}s"
  end
end

puts "Ruby Units Parser Performance Benchmark"
puts "=" * 50
puts "Test expressions: #{TEST_EXPRESSIONS.length}"
puts "Iterations: 1000"
puts

# Benchmark both parsers
legacy_results = benchmark_parser(false)
new_results = benchmark_parser(true)

# Calculate improvement
time_improvement = ((legacy_results[:total_time] - new_results[:total_time]) / legacy_results[:total_time]) * 100
speed_multiplier = legacy_results[:total_time] / new_results[:total_time]

puts "Results:"
puts "-" * 30

puts "Legacy Parser:"
puts "  Total time: #{format_time(legacy_results[:total_time])}"
puts "  Avg per expression: #{format_time(legacy_results[:avg_per_expression])}"
puts "  Expressions/second: #{legacy_results[:expressions_per_second].round(0)}"
puts

puts "New Parser:"
puts "  Total time: #{format_time(new_results[:total_time])}"
puts "  Avg per expression: #{format_time(new_results[:avg_per_expression])}"
puts "  Expressions/second: #{new_results[:expressions_per_second].round(0)}"
puts

puts "Performance Improvement:"
puts "  Time reduction: #{time_improvement.round(1)}%"
puts "  Speed multiplier: #{speed_multiplier.round(1)}x faster"
puts

# Test specific expressions
puts "Individual Expression Performance:"
puts "-" * 30

complex_expressions = [
  "9.8 kg*m/s^2",
  "100 km/h", 
  "kg*m^2/s^3",
  "1e-11 m^3"
]

complex_expressions.each do |expr|
  puts "\nExpression: #{expr}"
  
  # Legacy
  RubyUnits.configure { |c| c.use_new_parser = false }
  legacy_time = Benchmark.measure { 100.times { RubyUnits::Unit.new(expr) } }.real / 100
  
  # New
  RubyUnits.configure { |c| c.use_new_parser = true }
  new_time = Benchmark.measure { 100.times { RubyUnits::Unit.new(expr) } }.real / 100
  
  improvement = ((legacy_time - new_time) / legacy_time) * 100
  
  puts "  Legacy: #{format_time(legacy_time)}"
  puts "  New: #{format_time(new_time)}"
  puts "  Improvement: #{improvement.round(1)}%"
end

# Test with unique expressions to avoid caching
puts "\nUnique Expression Performance (No Caching):"
puts "-" * 45

def benchmark_unique_expressions(use_new_parser, iterations = 1000)
  RubyUnits.configure do |config|
    config.use_new_parser = use_new_parser
    config.compatibility_mode = false
  end
  
  # Templates for generating unique expressions
  templates = [
    "%{num} kg",
    "%{num} m/s",
    "%{num} kg/m^3", 
    "%{num} m^2",
    "%{num} km/h",
    "%{num} degC",
    "%{num} Hz",
    "%{num} kg*m/s^2"
  ]
  
  # Warm up with a few unique expressions
  5.times do |i|
    templates.each { |template| RubyUnits::Unit.new(template % {num: rand(1000)}) rescue nil }
  end
  
  # Benchmark with completely unique expressions each time
  total_time = Benchmark.measure do
    iterations.times do
      templates.each do |template|
        unique_expr = template % {num: rand(100000) + rand.round(3)}
        RubyUnits::Unit.new(unique_expr) rescue nil
      end
    end
  end.real
  
  {
    parser: use_new_parser ? "New" : "Legacy",
    total_time: total_time,
    avg_per_expression: total_time / (iterations * templates.length),
    expressions_per_second: (iterations * templates.length) / total_time,
    template_count: templates.length
  }
end

# Benchmark unique expressions
legacy_unique = benchmark_unique_expressions(false)
new_unique = benchmark_unique_expressions(true)

unique_improvement = ((legacy_unique[:total_time] - new_unique[:total_time]) / legacy_unique[:total_time]) * 100
unique_speedup = legacy_unique[:total_time] / new_unique[:total_time]

puts "Legacy Parser (unique expressions):"
puts "  Total time: #{format_time(legacy_unique[:total_time])}"
puts "  Avg per expression: #{format_time(legacy_unique[:avg_per_expression])}"
puts "  Expressions/second: #{legacy_unique[:expressions_per_second].round(0)}"
puts

puts "New Parser (unique expressions):"
puts "  Total time: #{format_time(new_unique[:total_time])}"
puts "  Avg per expression: #{format_time(new_unique[:avg_per_expression])}"
puts "  Expressions/second: #{new_unique[:expressions_per_second].round(0)}"
puts

puts "Unique Expression Performance:"
puts "  Time reduction: #{unique_improvement.round(1)}%"
puts "  Speed multiplier: #{unique_speedup.round(1)}x faster"
puts "  Templates tested: #{legacy_unique[:template_count]}"

puts "\nMemory Usage Comparison:"
puts "-" * 30

# Simple memory test
RubyUnits.configure { |c| c.use_new_parser = false }
before_legacy = `ps -o rss= -p #{Process.pid}`.to_i
1000.times { RubyUnits::Unit.new("kg*m/s^2") }
after_legacy = `ps -o rss= -p #{Process.pid}`.to_i
legacy_memory = after_legacy - before_legacy

RubyUnits.configure { |c| c.use_new_parser = true }
before_new = `ps -o rss= -p #{Process.pid}`.to_i
1000.times { RubyUnits::Unit.new("kg*m/s^2") }
after_new = `ps -o rss= -p #{Process.pid}`.to_i
new_memory = after_new - before_new

puts "Legacy parser memory delta: #{legacy_memory}KB"
puts "New parser memory delta: #{new_memory}KB"
if new_memory > 0
  memory_improvement = ((legacy_memory - new_memory).to_f / legacy_memory) * 100
  puts "Memory improvement: #{memory_improvement.round(1)}%"
end

puts "\n" + "=" * 70
puts "SUMMARY:"
puts "  Cached expressions: #{speed_multiplier.round(1)}x faster (#{time_improvement.round(1)}% improvement)"
puts "  Unique expressions: #{unique_speedup.round(1)}x faster (#{unique_improvement.round(1)}% improvement)"
puts "  Memory usage: #{new_memory}KB delta vs #{legacy_memory}KB delta"
puts "=" * 70