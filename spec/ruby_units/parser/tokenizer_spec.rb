# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ruby_units/parser/tokenizer"

RSpec.describe RubyUnits::Parser::Tokenizer do
  let(:tokenizer) { described_class.new }

  describe "#tokenize" do
    context "with simple numbers" do
      it "tokenizes integers" do
        tokens = tokenizer.tokenize("123")
        expect(tokens.map(&:type)).to eq([:number, :eof])
        expect(tokens.map(&:value)).to eq(["123", ""])
      end

      it "tokenizes decimals" do
        tokens = tokenizer.tokenize("123.45")
        expect(tokens.map(&:type)).to eq([:number, :eof])
        expect(tokens.map(&:value)).to eq(["123.45", ""])
      end

      it "tokenizes scientific notation" do
        tokens = tokenizer.tokenize("1.23e-5")
        expect(tokens.map(&:type)).to eq([:number, :eof])
        expect(tokens.map(&:value)).to eq(["1.23e-5", ""])
      end

      it "tokenizes negative numbers" do
        tokens = tokenizer.tokenize("-123.45")
        expect(tokens.map(&:type)).to eq([:number, :eof])
        expect(tokens.map(&:value)).to eq(["-123.45", ""])
      end
    end

    context "with rational numbers" do
      it "tokenizes simple fractions" do
        tokens = tokenizer.tokenize("1/2")
        expect(tokens.map(&:type)).to eq([:number, :eof])
        expect(tokens.map(&:value)).to eq(["1/2", ""])
      end

      it "tokenizes mixed numbers" do
        tokens = tokenizer.tokenize("1 2/3")
        expect(tokens.map(&:type)).to eq([:number, :eof])
        expect(tokens.map(&:value)).to eq(["1 2/3", ""])
      end
    end

    context "with complex numbers" do
      it "tokenizes imaginary numbers" do
        tokens = tokenizer.tokenize("1+2i")
        expect(tokens.map(&:type)).to eq([:number, :eof])
        expect(tokens.map(&:value)).to eq(["1+2i", ""])
      end

      it "tokenizes pure imaginary numbers" do
        tokens = tokenizer.tokenize("2i")
        expect(tokens.map(&:type)).to eq([:number, :eof])
        expect(tokens.map(&:value)).to eq(["2i", ""])
      end
    end

    context "with time formats" do
      it "tokenizes time format components" do
        tokens = tokenizer.tokenize("12:34:56")
        # For now, time format is tokenized as separate numbers
        # The parser will handle combining them
        expect(tokens.map(&:type)).to eq([:number, :number, :number, :eof])
        expect(tokens.map(&:value)).to eq(["12", "34", "56", ""])
      end
    end

    context "with units" do
      it "tokenizes simple units" do
        tokens = tokenizer.tokenize("meter")
        expect(tokens.map(&:type)).to eq([:unit, :eof])
        expect(tokens.map(&:value)).to eq(["meter", ""])
      end

      it "tokenizes abbreviations" do
        tokens = tokenizer.tokenize("kg")
        expect(tokens.map(&:type)).to eq([:unit, :eof])
        expect(tokens.map(&:value)).to eq(["kg", ""])
      end

      it "tokenizes units with hyphens" do
        tokens = tokenizer.tokenize("foot-pound")
        expect(tokens.map(&:type)).to eq([:unit, :eof])
        expect(tokens.map(&:value)).to eq(["foot-pound", ""])
      end
    end

    context "with special symbols" do
      it "tokenizes degree symbol" do
        tokens = tokenizer.tokenize("°C")
        expect(tokens.map(&:type)).to eq([:unit, :eof])
        expect(tokens.map(&:value)).to eq(["°C", ""])
      end

      it "tokenizes foot symbol" do
        tokens = tokenizer.tokenize("'")
        expect(tokens.map(&:type)).to eq([:unit, :eof])
        expect(tokens.map(&:value)).to eq(["'", ""])
      end

      it "tokenizes inch symbol" do
        tokens = tokenizer.tokenize('"')
        expect(tokens.map(&:type)).to eq([:unit, :eof])
        expect(tokens.map(&:value)).to eq(['"', ""])
      end

      it "tokenizes dollar symbol" do
        tokens = tokenizer.tokenize("$")
        expect(tokens.map(&:type)).to eq([:unit, :eof])
        expect(tokens.map(&:value)).to eq(["$", ""])
      end

      it "tokenizes percent symbol" do
        tokens = tokenizer.tokenize("%")
        expect(tokens.map(&:type)).to eq([:unit, :eof])
        expect(tokens.map(&:value)).to eq(["%", ""])
      end
    end

    context "with operators" do
      it "tokenizes multiplication" do
        tokens = tokenizer.tokenize("*")
        expect(tokens.map(&:type)).to eq([:operator, :eof])
        expect(tokens.map(&:value)).to eq(["*", ""])
      end

      it "tokenizes division" do
        tokens = tokenizer.tokenize("/")
        expect(tokens.map(&:type)).to eq([:operator, :eof])
        expect(tokens.map(&:value)).to eq(["/", ""])
      end

      it "tokenizes exponentiation" do
        tokens = tokenizer.tokenize("^")
        expect(tokens.map(&:type)).to eq([:operator, :eof])
        expect(tokens.map(&:value)).to eq(["^", ""])
      end
    end

    context "with parentheses" do
      it "tokenizes left parenthesis" do
        tokens = tokenizer.tokenize("(")
        expect(tokens.map(&:type)).to eq([:lparen, :eof])
        expect(tokens.map(&:value)).to eq(["(", ""])
      end

      it "tokenizes right parenthesis" do
        tokens = tokenizer.tokenize(")")
        expect(tokens.map(&:type)).to eq([:rparen, :eof])
        expect(tokens.map(&:value)).to eq([")", ""])
      end
    end

    context "with complex expressions" do
      it "tokenizes number with unit" do
        tokens = tokenizer.tokenize("5 meters")
        expect(tokens.map(&:type)).to eq([:number, :unit, :eof])
        expect(tokens.map(&:value)).to eq(["5", "meters", ""])
      end

      it "tokenizes compound units" do
        tokens = tokenizer.tokenize("kg*m/s^2")
        expect(tokens.map(&:type)).to eq([:unit, :operator, :unit, :operator, :unit, :operator, :number, :eof])
        expect(tokens.map(&:value)).to eq(["kg", "*", "m", "/", "s", "^", "2", ""])
      end

      it "tokenizes parenthesized expressions" do
        tokens = tokenizer.tokenize("(kg*m)/s^2")
        expect(tokens.map(&:type)).to eq([:lparen, :unit, :operator, :unit, :rparen, :operator, :unit, :operator, :number, :eof])
        expect(tokens.map(&:value)).to eq(["(", "kg", "*", "m", ")", "/", "s", "^", "2", ""])
      end

      it "tokenizes feet and inches format" do
        tokens = tokenizer.tokenize("6'4\"")
        expect(tokens.map(&:type)).to eq([:number, :unit, :number, :unit, :eof])
        expect(tokens.map(&:value)).to eq(["6", "'", "4", '"', ""])
      end
    end

    context "with whitespace" do
      it "skips whitespace" do
        tokens = tokenizer.tokenize("  5   meters  ")
        expect(tokens.map(&:type)).to eq([:number, :unit, :eof])
        expect(tokens.map(&:value)).to eq(["5", "meters", ""])
      end
    end

    context "with empty input" do
      it "returns only EOF token" do
        tokens = tokenizer.tokenize("")
        expect(tokens.map(&:type)).to eq([:eof])
        expect(tokens.map(&:value)).to eq([""])
      end
    end

    context "with malformed input" do
      it "skips unknown characters" do
        tokens = tokenizer.tokenize("5@meters")
        expect(tokens.map(&:type)).to eq([:number, :unit, :eof])
        expect(tokens.map(&:value)).to eq(["5", "meters", ""])
      end
    end
  end
end