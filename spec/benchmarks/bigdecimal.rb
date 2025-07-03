# frozen_string_literal: true

require_relative "../spec_helper"
require "bigdecimal"
require "bigdecimal/util"
require "benchmark"
require "ruby-prof"

puts "BigDecimal Units Benchmark - Parser Comparison"
puts "=" * 55

# Test data - various gallon measurements
test_data = [
  [2.025, "gal"],
  [5.575, "gal"],
  [8.975, "gal"],
  [1.5, "gal"],
  [9, "gal"],
  [1.85, "gal"],
  [2.25, "gal"],
  [1.05, "gal"],
  [4.725, "gal"],
  [3.55, "gal"],
  [4.725, "gal"],
  [3.75, "gal"],
  [6.275, "gal"],
  [0.525, "gal"],
  [3.475, "gal"],
  [0.85, "gal"]
]

def test_with_parser(parser_name, use_new_parser, test_data)
  puts "\n#{parser_name} Parser Results:"
  puts "-" * 30
  
  # Configure parser
  RubyUnits.configure do |config|
    config.use_new_parser = use_new_parser
  end
  
  # Create units with BigDecimal precision
  units = test_data.map { |ns, nu| Unit.new(ns.to_d, nu) }
  
  # Benchmark addition
  addition_time = Benchmark.measure do
    result = units.reduce(:+)
    puts "Sum: #{result}"
  end.real
  
  # Benchmark subtraction  
  subtraction_time = Benchmark.measure do
    result = units.reduce(:-)
    puts "Difference: #{result}"
  end.real
  
  puts "Addition time: #{(addition_time * 1000).round(2)}ms"
  puts "Subtraction time: #{(subtraction_time * 1000).round(2)}ms"
  puts "Total time: #{((addition_time + subtraction_time) * 1000).round(2)}ms"
  
  return addition_time + subtraction_time
end

# Test with legacy parser
legacy_time = test_with_parser("Legacy", false, test_data)

# Test with new parser  
new_time = test_with_parser("New", true, test_data)

# Compare results
puts "\nComparison:"
puts "-" * 15
improvement = ((legacy_time - new_time) / legacy_time * 100).round(1)
speedup = (legacy_time / new_time).round(1)

puts "Legacy total time: #{(legacy_time * 1000).round(2)}ms"
puts "New total time: #{(new_time * 1000).round(2)}ms"
puts "Improvement: #{improvement}%"
puts "Speedup: #{speedup}x"

# Profile the new parser version for detailed analysis
puts "\nDetailed Profile (New Parser):"
puts "-" * 35

RubyUnits.configure { |config| config.use_new_parser = true }
units = test_data.map { |ns, nu| Unit.new(ns.to_d, nu) }

result = RubyProf::Profile.profile do
  units.reduce(:+)
  units.reduce(:-)
end

# Print a focused profile showing just the top methods
printer = RubyProf::FlatPrinter.new(result)
printer.print(STDOUT, { min_percent: 2 })
