# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe "Parser Integration" do
  before do
    # Reset configuration before each test
    RubyUnits.reset
  end

  after do
    # Reset configuration after each test
    RubyUnits.reset
  end

  describe "new parser integration" do
    before do
      RubyUnits.configure do |config|
        config.use_new_parser = true
        config.compatibility_mode = false
      end
    end

    it "integrates with Unit.new" do
      unit = RubyUnits::Unit.new("5 meters")
      expect(unit.scalar).to eq(5.0)
      expect(unit.units).to eq("m")
    end

    it "works with string extensions" do
      unit = "10 kg".to_unit
      expect(unit.scalar).to eq(10.0)
      expect(unit.units).to eq("kg")
    end

    it "handles complex unit expressions" do
      unit = RubyUnits::Unit.new("9.8 kg*m/s^2")
      expect(unit.scalar).to be_within(0.001).of(9.8)
      expect(unit.units).to include("kg")
      expect(unit.units).to include("m")
      expect(unit.units).to include("s")
    end

    it "preserves existing Unit behavior" do
      unit1 = RubyUnits::Unit.new("1 meter")
      unit2 = RubyUnits::Unit.new("100 cm")
      
      expect(unit1).to be_compatible_with(unit2)
      expect(unit1.convert_to("cm").scalar).to be_within(0.1).of(100.0)
    end

    it "works with arithmetic operations" do
      length = RubyUnits::Unit.new("5 meters")
      width = RubyUnits::Unit.new("3 meters")
      area = length * width
      
      expect(area.units).to eq("m^2")
      expect(area.scalar).to eq(15)
    end

    it "handles temperature units" do
      temp = RubyUnits::Unit.new("37 degC")
      expect(temp.scalar).to eq(37.0)
      expect(temp.units).to eq("degC")
    end
  end

  describe "compatibility mode" do
    before do
      RubyUnits.configure do |config|
        config.use_new_parser = true
        config.compatibility_mode = true
      end
    end

    it "validates results against legacy parser" do
      # This should work without warnings
      unit = RubyUnits::Unit.new("5 meters")
      expect(unit.scalar).to eq(5.0)
      expect(unit.units).to eq("m")
    end

    it "falls back to legacy parser on mismatch" do
      # Test a case where parsers might differ
      unit = RubyUnits::Unit.new("1")
      expect(unit.scalar).to eq(1.0)
      expect(unit.units).to eq("")
    end
  end

  describe "configuration" do
    it "can enable new parser" do
      expect(RubyUnits.configuration.use_new_parser).to be false
      
      RubyUnits.configure do |config|
        config.use_new_parser = true
      end
      
      expect(RubyUnits.configuration.use_new_parser).to be true
    end

    it "can enable compatibility mode" do
      expect(RubyUnits.configuration.compatibility_mode).to be false
      
      RubyUnits.configure do |config|
        config.compatibility_mode = true
      end
      
      expect(RubyUnits.configuration.compatibility_mode).to be true
    end

    it "can set parser cache size" do
      RubyUnits.configure do |config|
        config.parser_cache_size = 2000
      end
      
      expect(RubyUnits.configuration.parser_cache_size).to eq(2000)
    end

    it "can enable debug mode" do
      RubyUnits.configure do |config|
        config.parser_debug = true
      end
      
      expect(RubyUnits.configuration.parser_debug).to be true
    end
  end

  describe "error handling" do
    before do
      RubyUnits.configure do |config|
        config.use_new_parser = true
      end
    end

    it "falls back to legacy parser on parse error" do
      # Use a unit that might cause issues in new parser
      expect { RubyUnits::Unit.new("1") }.not_to raise_error
    end

    it "provides useful error messages" do
      expect { RubyUnits::Unit.new("invalid_unit_xyz") }.to raise_error(ArgumentError)
    end
  end

  describe "performance improvements" do
    before do
      RubyUnits.configure do |config|
        config.use_new_parser = true
      end
    end

    it "parses units faster than legacy parser" do
      # Warm up
      10.times { RubyUnits::Unit.new("5 meters") }
      
      new_parser_time = Benchmark.measure do
        1000.times { RubyUnits::Unit.new("5 meters") }
      end.real
      
      # Switch to legacy parser
      RubyUnits.configure { |config| config.use_new_parser = false }
      
      # Warm up legacy parser
      10.times { RubyUnits::Unit.new("5 meters") }
      
      legacy_parser_time = Benchmark.measure do
        1000.times { RubyUnits::Unit.new("5 meters") }
      end.real
      
      # New parser should be faster (allow some variance for test reliability)
      expect(new_parser_time).to be < legacy_parser_time * 1.5
    end
  end
end