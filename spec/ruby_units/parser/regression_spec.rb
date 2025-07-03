# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe "Parser Regression Tests" do
  # Test expressions that should work identically in both parsers
  REGRESSION_TEST_CASES = [
    # Basic numbers
    "1",
    "1.0",
    "123",
    "123.456",
    "-42",
    "-3.14",
    "1e5",
    "1.23e-5",
    "1E+10",
    
    # Rational numbers
    "1/2",
    "2/3", 
    "1 2/3",
    "3 1/4",
    
    # Basic units
    "meter",
    "m",
    "kilogram", 
    "kg",
    "second",
    "s",
    "foot",
    "ft",
    "inch",
    "in",
    
    # Units with scalars
    "5 meters",
    "10 kg",
    "3.14 seconds",
    "1.5 feet",
    "100 cm",
    
    # Prefixed units
    "kilometer",
    "km",
    "millimeter",
    "mm",
    "micrometer",
    "kilogram",
    "milligram",
    "mg",
    
    # Compound units
    "m/s",
    "kg*m",
    "kg/m^3",
    "m^2",
    "m^3",
    "s^-1",
    "kg*m/s^2",
    "kg*m^2/s^2",
    "m/s^2",
    
    # With scalars
    "5 m/s",
    "9.8 m/s^2",
    "100 kg*m/s^2",
    "3.14 m^2",
    
    # Parentheses
    "(kg*m)",
    "(kg*m)/s^2",
    "kg*(m/s^2)",
    
    # Special formats
    "37 degC",
    "98.6 tempF",
    "50%",
    
    # Time formats
    "12:34:56",
    "1:30",
    
    # Currency
    "$15.50",
    
    # Temperature variations
    "0 degC",
    "100 degC",
    "32 tempF",
    "212 tempF",
    "273.15 tempK",
    
    # Scientific units
    "1 Hz",
    "60 Hz",
    "1 N",
    "1 J",
    "1 W",
    "1 Pa",
    "1 V",
    "1 A",
    "1 Ohm",
    
    # Complex expressions
    "kg*m^2/s^3",
    "A*s",
    "kg*m^2/(A*s^3)",
    "kg*m^2/(A^2*s^3)",
    
    # Edge cases
    "1 unity",
    "1 <1>",
  ].freeze

  before(:all) do
    # Ensure all unit definitions are loaded
    require_relative "../../../lib/ruby_units/unit_definitions"
    
    # Force initialization by creating a unit
    RubyUnits::Unit.new("1 meter")
  end

  after do
    # Reset configuration after each test
    RubyUnits.reset
  end

  describe "backward compatibility" do
    REGRESSION_TEST_CASES.each do |test_case|
      context "with expression '#{test_case}'" do
        it "produces identical results in both parsers" do
          # Parse with legacy parser
          RubyUnits.configure { |config| config.use_new_parser = false }
          
          legacy_unit = begin
            RubyUnits::Unit.new(test_case)
          rescue => e
            { error: e.class.name, message: e.message }
          end
          
          # Parse with new parser
          RubyUnits.configure { |config| config.use_new_parser = true }
          
          new_unit = begin
            RubyUnits::Unit.new(test_case)
          rescue => e
            { error: e.class.name, message: e.message }
          end
          
          # Compare results
          if legacy_unit.is_a?(Hash) && new_unit.is_a?(Hash)
            # Both failed - errors should be similar
            expect(new_unit[:error]).to eq(legacy_unit[:error])
          elsif legacy_unit.is_a?(Hash)
            # Legacy failed, new succeeded - this is an improvement for certain expressions
            known_improvements = ['(kg*m)/s^2', '(kg*m)', 'kg*(m/s^2)']
            if known_improvements.include?(test_case)
              # These are known improvements - the new parser handles parentheses
              expect(new_unit).to be_a(RubyUnits::Unit)
            else
              pending "New parser succeeded where legacy failed: #{test_case}"
            end
          elsif new_unit.is_a?(Hash)
            # New failed, legacy succeeded - this is not acceptable
            fail "New parser failed where legacy succeeded: #{test_case} - #{new_unit[:message]}"
          else
            # Both succeeded - compare values
            expect(new_unit.scalar).to be_within(1e-10).of(legacy_unit.scalar), 
              "Scalar mismatch for '#{test_case}': new=#{new_unit.scalar}, legacy=#{legacy_unit.scalar}"
            
            expect(normalize_units(new_unit.numerator)).to eq(normalize_units(legacy_unit.numerator)),
              "Numerator mismatch for '#{test_case}': new=#{new_unit.numerator}, legacy=#{legacy_unit.numerator}"
            
            expect(normalize_units(new_unit.denominator)).to eq(normalize_units(legacy_unit.denominator)),
              "Denominator mismatch for '#{test_case}': new=#{new_unit.denominator}, legacy=#{legacy_unit.denominator}"
            
            # Additional checks
            expect(new_unit.units).to eq(legacy_unit.units),
              "Units string mismatch for '#{test_case}': new='#{new_unit.units}', legacy='#{legacy_unit.units}'"
            
            expect(new_unit.kind).to eq(legacy_unit.kind),
              "Kind mismatch for '#{test_case}': new=#{new_unit.kind}, legacy=#{legacy_unit.kind}"
          end
        end
      end
    end
  end

  describe "all unit definitions compatibility" do
    it "handles all defined unit aliases" do
      RubyUnits.configure { |config| config.use_new_parser = false }
      legacy_results = {}
      
      RubyUnits::Unit.unit_map.keys.first(50).each do |unit_alias|
        begin
          unit = RubyUnits::Unit.new(unit_alias.to_s)
          legacy_results[unit_alias] = {
            scalar: unit.scalar,
            numerator: unit.numerator,
            denominator: unit.denominator
          }
        rescue => e
          legacy_results[unit_alias] = { error: e.class.name }
        end
      end
      
      RubyUnits.configure { |config| config.use_new_parser = true }
      
      legacy_results.each do |unit_alias, expected|
        begin
          unit = RubyUnits::Unit.new(unit_alias.to_s)
          actual = {
            scalar: unit.scalar,
            numerator: unit.numerator,
            denominator: unit.denominator
          }
          
          if expected.key?(:error)
            fail "New parser succeeded for '#{unit_alias}' where legacy failed"
          else
            expect(actual[:scalar]).to be_within(1e-10).of(expected[:scalar])
            expect(normalize_units(actual[:numerator])).to eq(normalize_units(expected[:numerator]))
            expect(normalize_units(actual[:denominator])).to eq(normalize_units(expected[:denominator]))
          end
        rescue => e
          if expected.key?(:error)
            expect(e.class.name).to eq(expected[:error])
          else
            fail "New parser failed for '#{unit_alias}': #{e.message}"
          end
        end
      end
    end
  end

  describe "real world expressions" do
    real_world_cases = [
      "5 feet 6 inches",
      "8 lbs 8 oz", 
      "14 stone 3 lbs",
      "98.6 tempF",
      "37 degC",
      "standard-gravitation",
      "1 astronomical-unit",
      "1 light-year",
      "1 mph",
      "55 mph",
      "100 km/h",
      "9.8 m/s^2",
      "6.67e-11 m^3/(kg*s^2)",
      "3e8 m/s",
      "1.6e-19 C",
      "6.022e23 /mol",
      "1.38e-23 J/K",
      "8.314 J/(mol*K)",
      "101325 Pa",
      "1 atm",
      "760 torr",
    ]

    real_world_cases.each do |expression|
      it "handles real world expression: #{expression}" do
        # Test with legacy parser
        RubyUnits.configure { |config| config.use_new_parser = false }
        legacy_result = begin
          RubyUnits::Unit.new(expression)
        rescue => e
          { error: e }
        end

        # Test with new parser  
        RubyUnits.configure { |config| config.use_new_parser = true }
        new_result = begin
          RubyUnits::Unit.new(expression)
        rescue => e
          { error: e }
        end

        # Compare results
        if legacy_result.is_a?(Hash) && new_result.is_a?(Hash)
          # Both failed
          expect(new_result[:error].class).to eq(legacy_result[:error].class)
        elsif legacy_result.is_a?(Hash)
          # Only legacy failed - might be improvement
          pending "New parser handles '#{expression}' better than legacy"
        elsif new_result.is_a?(Hash)
          # Only new failed - regression
          fail "New parser regression for '#{expression}': #{new_result[:error].message}"
        else
          # Both succeeded - should be equivalent
          expect(new_result.scalar).to be_within(1e-8).of(legacy_result.scalar)
          expect(new_result.base_scalar).to be_within(1e-8).of(legacy_result.base_scalar)
          expect(new_result.kind).to eq(legacy_result.kind)
        end
      end
    end
  end

  describe "performance regression" do
    it "new parser is not significantly slower than legacy parser" do
      test_expressions = REGRESSION_TEST_CASES.first(20)
      
      # Benchmark legacy parser
      RubyUnits.configure { |config| config.use_new_parser = false }
      
      # Warm up
      test_expressions.each { |expr| RubyUnits::Unit.new(expr) rescue nil }
      
      legacy_time = Benchmark.measure do
        100.times do
          test_expressions.each { |expr| RubyUnits::Unit.new(expr) rescue nil }
        end
      end.real
      
      # Benchmark new parser
      RubyUnits.configure { |config| config.use_new_parser = true }
      
      # Warm up
      test_expressions.each { |expr| RubyUnits::Unit.new(expr) rescue nil }
      
      new_time = Benchmark.measure do
        100.times do
          test_expressions.each { |expr| RubyUnits::Unit.new(expr) rescue nil }
        end
      end.real
      
      puts "\nPerformance comparison:"
      puts "Legacy parser: #{legacy_time.round(4)}s"
      puts "New parser: #{new_time.round(4)}s"
      puts "Improvement: #{((legacy_time - new_time) / legacy_time * 100).round(1)}%"
      
      # New parser should not be significantly slower
      expect(new_time).to be < legacy_time * 2.0, "New parser is too slow compared to legacy"
    end
  end

  private

  def normalize_units(unit_array)
    return [] if unit_array.nil? || unit_array.empty? || unit_array == ["<1>"]
    unit_array.sort
  end
end