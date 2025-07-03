# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ruby_units/parser/unit_trie"

RSpec.describe RubyUnits::Parser::UnitTrie do
  let(:trie) { described_class.new }

  before do
    # Ensure unit definitions are loaded
    require_relative "../../../lib/ruby_units/unit_definitions"
  end

  describe "#lookup_unit" do
    it "finds basic SI units" do
      unit_info = trie.lookup_unit("meter")
      expect(unit_info).not_to be_nil
      expect(unit_info.name).to eq("<meter>")
    end

    it "finds unit aliases" do
      unit_info = trie.lookup_unit("m")
      expect(unit_info).not_to be_nil
      expect(unit_info.name).to eq("<meter>")
    end

    it "finds imperial units" do
      unit_info = trie.lookup_unit("foot")
      expect(unit_info).not_to be_nil
      expect(unit_info.name).to eq("<foot>")
    end

    it "finds unit abbreviations" do
      unit_info = trie.lookup_unit("ft")
      expect(unit_info).not_to be_nil
      expect(unit_info.name).to eq("<foot>")
    end

    it "returns nil for unknown units" do
      unit_info = trie.lookup_unit("nonexistent")
      expect(unit_info).to be_nil
    end

    it "is case sensitive" do
      unit_info = trie.lookup_unit("METER")
      expect(unit_info).to be_nil
    end
  end

  describe "#lookup_prefix" do
    it "finds common prefixes" do
      prefix_info = trie.lookup_prefix("kilo")
      expect(prefix_info).not_to be_nil
      expect(prefix_info[:name]).to eq("<kilo>")
      expect(prefix_info[:scalar]).to eq(1000)
    end

    it "finds prefix abbreviations" do
      prefix_info = trie.lookup_prefix("k")
      expect(prefix_info).not_to be_nil
      expect(prefix_info[:name]).to eq("<kilo>")
      expect(prefix_info[:scalar]).to eq(1000)
    end

    it "finds micro prefix" do
      prefix_info = trie.lookup_prefix("micro")
      expect(prefix_info).not_to be_nil
      expect(prefix_info[:name]).to eq("<micro>")
      expect(prefix_info[:scalar]).to eq(1e-6)
    end

    it "returns nil for unknown prefixes" do
      prefix_info = trie.lookup_prefix("nonexistent")
      expect(prefix_info).to be_nil
    end
  end

  describe "#parse_unit_with_prefix" do
    it "parses simple units without prefix" do
      prefix_info, unit_info = trie.parse_unit_with_prefix("meter")
      expect(prefix_info).to be_nil
      expect(unit_info).not_to be_nil
      expect(unit_info.name).to eq("<meter>")
    end

    it "parses units with prefix" do
      prefix_info, unit_info = trie.parse_unit_with_prefix("kilometer")
      expect(prefix_info).not_to be_nil
      expect(prefix_info[:name]).to eq("<kilo>")
      expect(prefix_info[:scalar]).to eq(1000)
      expect(unit_info).not_to be_nil
      expect(unit_info.name).to eq("<meter>")
    end

    it "prefers longer prefix matches" do
      # If both "micro" and "m" are valid prefixes, prefer "micro"
      prefix_info, unit_info = trie.parse_unit_with_prefix("micrometer")
      expect(prefix_info).not_to be_nil
      expect(prefix_info[:name]).to eq("<micro>")
      expect(unit_info).not_to be_nil
      expect(unit_info.name).to eq("<meter>")
    end

    it "handles abbreviated prefixes" do
      prefix_info, unit_info = trie.parse_unit_with_prefix("km")
      expect(prefix_info).not_to be_nil
      expect(prefix_info[:name]).to eq("<kilo>")
      expect(unit_info).not_to be_nil
      expect(unit_info.name).to eq("<meter>")
    end

    it "returns nil for unknown combinations" do
      prefix_info, unit_info = trie.parse_unit_with_prefix("unknownunit")
      expect(prefix_info).to be_nil
      expect(unit_info).to be_nil
    end

    it "handles edge cases with empty strings" do
      prefix_info, unit_info = trie.parse_unit_with_prefix("")
      expect(prefix_info).to be_nil
      expect(unit_info).to be_nil
    end
  end

  describe "#find_all_matches" do
    it "finds all possible matches for ambiguous strings" do
      matches = trie.find_all_matches("km")
      expect(matches.length).to be >= 1
      
      # Should find kilometer (kilo + meter)
      kilo_meter = matches.find { |prefix_info, unit_info| 
        prefix_info&.dig(:name) == "<kilo>" && unit_info&.name == "<meter>" 
      }
      expect(kilo_meter).not_to be_nil
    end

    it "returns empty array for no matches" do
      matches = trie.find_all_matches("nonexistent")
      expect(matches).to be_empty
    end
  end

  describe "performance" do
    it "builds trie efficiently" do
      expect { trie.lookup_unit("meter") }.not_to raise_error
    end

    it "handles many lookups efficiently" do
      start_time = Time.now
      1000.times { trie.lookup_unit("meter") }
      end_time = Time.now
      
      elapsed = end_time - start_time
      expect(elapsed).to be < 0.1, "Lookups took #{elapsed}s, should be < 0.1s"
    end
  end
end