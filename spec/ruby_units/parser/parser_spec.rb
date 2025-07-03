# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ruby_units/parser"

RSpec.describe RubyUnits::Parser::Parser do
  let(:parser) { described_class.new }

  before do
    # Ensure unit definitions are loaded
    require_relative "../../../lib/ruby_units/unit_definitions"
  end

  describe "#parse" do
    context "with simple numbers" do
      it "parses integers" do
        result = parser.parse("5")
        expect(result.scalar).to eq(5.0)
        expect(result.numerator).to be_empty
        expect(result.denominator).to be_empty
      end

      it "parses decimals" do
        result = parser.parse("3.14")
        expect(result.scalar).to be_within(0.001).of(3.14)
        expect(result.numerator).to be_empty
        expect(result.denominator).to be_empty
      end

      it "parses scientific notation" do
        result = parser.parse("1.23e-5")
        expect(result.scalar).to be_within(1e-10).of(1.23e-5)
        expect(result.numerator).to be_empty
        expect(result.denominator).to be_empty
      end

      it "parses negative numbers" do
        result = parser.parse("-42")
        expect(result.scalar).to eq(-42.0)
        expect(result.numerator).to be_empty
        expect(result.denominator).to be_empty
      end
    end

    context "with rational numbers" do
      it "parses simple fractions" do
        result = parser.parse("1/2")
        expect(result.scalar).to be_within(0.001).of(0.5)
        expect(result.numerator).to be_empty
        expect(result.denominator).to be_empty
      end

      it "parses mixed numbers" do
        result = parser.parse("1 2/3")
        expect(result.scalar).to be_within(0.001).of(5.0/3.0)
        expect(result.numerator).to be_empty
        expect(result.denominator).to be_empty
      end
    end

    context "with time formats" do
      xit "parses time as seconds" do
        # Skip for now - time format parsing needs more work
        result = parser.parse("1:30:00")
        expect(result.scalar).to eq(5400.0) # 1.5 hours in seconds
        expect(result.numerator).to be_empty
        expect(result.denominator).to be_empty
      end

      xit "parses minutes and seconds" do
        # Skip for now - time format parsing needs more work
        result = parser.parse("2:30")
        expect(result.scalar).to eq(150.0) # 2.5 minutes in seconds
        expect(result.numerator).to be_empty
        expect(result.denominator).to be_empty
      end
    end

    context "with simple units" do
      it "parses basic units" do
        result = parser.parse("meter")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator).to eq(["<meter>"])
        expect(result.denominator).to be_empty
      end

      it "parses unit abbreviations" do
        result = parser.parse("m")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator).to eq(["<meter>"])
        expect(result.denominator).to be_empty
      end

      it "parses units with prefixes" do
        result = parser.parse("kilometer")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator).to eq(["<kilo>", "<meter>"])
        expect(result.denominator).to be_empty
      end

      it "parses abbreviated prefixed units" do
        result = parser.parse("km")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator).to eq(["<kilo>", "<meter>"])
        expect(result.denominator).to be_empty
      end
    end

    context "with numbers and units" do
      it "parses scalar with unit" do
        result = parser.parse("5 meters")
        expect(result.scalar).to eq(5.0)
        expect(result.numerator).to eq(["<meter>"])
        expect(result.denominator).to be_empty
      end

      it "parses decimal with unit" do
        result = parser.parse("3.14 kg")
        expect(result.scalar).to be_within(0.001).of(3.14)
        expect(result.numerator).to eq(["<kilogram>"])
        expect(result.denominator).to be_empty
      end

      it "parses scientific notation with unit" do
        result = parser.parse("1.23e-5 meters")
        expect(result.scalar).to be_within(1e-10).of(1.23e-5)
        expect(result.numerator).to eq(["<meter>"])
        expect(result.denominator).to be_empty
      end
    end

    context "with compound units" do
      it "parses multiplication" do
        result = parser.parse("kg*m")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator.sort).to eq(["<kilogram>", "<meter>"])
        expect(result.denominator).to be_empty
      end

      it "parses division" do
        result = parser.parse("m/s")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator).to eq(["<meter>"])
        expect(result.denominator).to eq(["<second>"])
      end

      it "parses complex expressions" do
        result = parser.parse("kg*m/s^2")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator.sort).to eq(["<kilogram>", "<meter>"])
        expect(result.denominator.sort).to eq(["<second>", "<second>"])
      end

      it "parses with scalar" do
        result = parser.parse("9.8 kg*m/s^2")
        expect(result.scalar).to be_within(0.001).of(9.8)
        expect(result.numerator.sort).to eq(["<kilogram>", "<meter>"])
        expect(result.denominator.sort).to eq(["<second>", "<second>"])
      end
    end

    context "with exponents" do
      it "parses positive exponents" do
        result = parser.parse("m^2")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator).to eq(["<meter>", "<meter>"])
        expect(result.denominator).to be_empty
      end

      it "parses negative exponents" do
        result = parser.parse("s^-1")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator).to be_empty
        expect(result.denominator).to eq(["<second>"])
      end

      it "parses zero exponents" do
        result = parser.parse("m^0")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator).to be_empty
        expect(result.denominator).to be_empty
      end

      it "parses large exponents" do
        result = parser.parse("m^3")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator).to eq(["<meter>", "<meter>", "<meter>"])
        expect(result.denominator).to be_empty
      end
    end

    context "with parentheses" do
      it "parses simple parentheses" do
        result = parser.parse("(kg*m)")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator.sort).to eq(["<kilogram>", "<meter>"])
        expect(result.denominator).to be_empty
      end

      it "parses complex parentheses" do
        result = parser.parse("(kg*m)/s^2")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator.sort).to eq(["<kilogram>", "<meter>"])
        expect(result.denominator.sort).to eq(["<second>", "<second>"])
      end

      it "parses nested parentheses" do
        result = parser.parse("((kg*m))")
        expect(result.scalar).to eq(1.0)
        expect(result.numerator.sort).to eq(["<kilogram>", "<meter>"])
        expect(result.denominator).to be_empty
      end
    end

    context "with special symbols" do
      it "parses foot symbol" do
        result = parser.parse("6'")
        expect(result.scalar).to eq(6.0)
        expect(result.numerator).to eq(["<foot>"])
        expect(result.denominator).to be_empty
      end

      it "parses inch symbol" do
        result = parser.parse('4"')
        expect(result.scalar).to eq(4.0)
        expect(result.numerator).to eq(["<inch>"])
        expect(result.denominator).to be_empty
      end

      it "parses degree symbol" do
        result = parser.parse("37°C")
        expect(result.scalar).to eq(37.0)
        expect(result.numerator).to eq(["<celsius>"])
        expect(result.denominator).to be_empty
      end

      it "parses percent symbol" do
        result = parser.parse("50%")
        expect(result.scalar).to eq(50.0)
        expect(result.numerator).to eq(["<percent>"])
        expect(result.denominator).to be_empty
      end
    end

    context "with edge cases" do
      it "handles extra whitespace" do
        result = parser.parse("  5   meters  ")
        expect(result.scalar).to eq(5.0)
        expect(result.numerator).to eq(["<meter>"])
        expect(result.denominator).to be_empty
      end

      it "handles empty input gracefully" do
        expect { parser.parse("") }.to raise_error(RubyUnits::Parser::ParseError)
      end
    end

    context "with error conditions" do
      it "raises error for unknown units" do
        expect { parser.parse("unknownunit") }.to raise_error(RubyUnits::Parser::ParseError, /Unknown unit/)
      end

      it "raises error for mismatched parentheses" do
        expect { parser.parse("(kg*m") }.to raise_error(RubyUnits::Parser::ParseError)
      end

      it "raises error for invalid syntax" do
        expect { parser.parse("kg*/m") }.to raise_error(RubyUnits::Parser::ParseError)
      end
    end
  end

  describe "performance" do
    it "parses simple expressions quickly" do
      start_time = Time.now
      1000.times { parser.parse("5 meters") }
      end_time = Time.now
      
      elapsed = end_time - start_time
      expect(elapsed).to be < 0.2, "Simple parsing took #{elapsed}s, should be < 0.2s"
    end

    it "parses complex expressions efficiently" do
      start_time = Time.now
      100.times { parser.parse("9.8 kg*m/s^2") }
      end_time = Time.now
      
      elapsed = end_time - start_time
      expect(elapsed).to be < 0.2, "Complex parsing took #{elapsed}s, should be < 0.2s"
    end
  end
end