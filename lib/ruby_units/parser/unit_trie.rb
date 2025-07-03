# frozen_string_literal: true

module RubyUnits
  module Parser
    # Trie (prefix tree) for efficient unit lookup
    class UnitTrie
      # Compact node representation for memory efficiency
      class TrieNode
        attr_accessor :children, :unit_info, :is_terminal, :prefix_info

        def initialize
          @children = {}
          @unit_info = nil
          @prefix_info = nil
          @is_terminal = false
        end

        def terminal?
          @is_terminal
        end

        def has_unit?
          !@unit_info.nil?
        end

        def has_prefix?
          !@prefix_info.nil?
        end
      end

      def initialize
        @root = TrieNode.new
        @built = false
      end

      # Build the trie from current unit definitions
      def build_trie
        return if @built

        # Build unit trie
        RubyUnits::Unit.unit_map.each do |unit_alias, canonical_name|
          unit_definition = RubyUnits::Unit.definitions[canonical_name]
          next unless unit_definition

          insert_unit(unit_alias.to_s, unit_definition)
        end

        # Build prefix trie
        RubyUnits::Unit.prefix_map.each do |prefix_alias, canonical_name|
          prefix_info = {
            name: canonical_name,
            scalar: RubyUnits::Unit.prefix_values[canonical_name]
          }
          insert_prefix(prefix_alias.to_s, prefix_info)
        end

        @built = true
      end

      # Look up a unit by name
      def lookup_unit(unit_name)
        build_trie unless @built
        
        node = traverse(unit_name)
        node&.has_unit? ? node.unit_info : nil
      end

      # Look up a prefix by name
      def lookup_prefix(prefix_name)
        build_trie unless @built
        
        node = traverse(prefix_name)
        node&.has_prefix? ? node.prefix_info : nil
      end

      # Try to parse a unit with optional prefix
      def parse_unit_with_prefix(unit_string)
        build_trie unless @built
        
        # Try exact match first
        unit_info = lookup_unit(unit_string)
        return [nil, unit_info] if unit_info

        # Try prefix + unit combinations
        # Sort prefixes by length (longest first) to prefer longer matches
        sorted_prefixes = RubyUnits::Unit.prefix_map.keys.sort_by { |p| -p.length }
        
        sorted_prefixes.each do |prefix|
          prefix_str = prefix.to_s
          next unless unit_string.start_with?(prefix_str)
          
          base_unit = unit_string[prefix_str.length..-1]
          next if base_unit.empty?
          
          unit_info = lookup_unit(base_unit)
          prefix_info = lookup_prefix(prefix_str)
          
          return [prefix_info, unit_info] if unit_info && prefix_info
        end

        [nil, nil]
      end

      # Get all possible unit matches for a string (for ambiguity detection)
      def find_all_matches(unit_string)
        build_trie unless @built
        
        matches = []
        
        # Direct unit match
        unit_info = lookup_unit(unit_string)
        matches << [nil, unit_info] if unit_info

        # Prefix + unit matches
        RubyUnits::Unit.prefix_map.keys.each do |prefix|
          prefix_str = prefix.to_s
          next unless unit_string.start_with?(prefix_str)
          
          base_unit = unit_string[prefix_str.length..-1]
          next if base_unit.empty?
          
          unit_info = lookup_unit(base_unit)
          prefix_info = lookup_prefix(prefix_str)
          
          matches << [prefix_info, unit_info] if unit_info && prefix_info
        end

        matches
      end

      private

      def insert_unit(unit_name, unit_definition)
        node = @root
        
        unit_name.each_char do |char|
          node.children[char] ||= TrieNode.new
          node = node.children[char]
        end
        
        node.unit_info = unit_definition
        node.is_terminal = true
      end

      def insert_prefix(prefix_name, prefix_info)
        node = @root
        
        prefix_name.each_char do |char|
          node.children[char] ||= TrieNode.new
          node = node.children[char]
        end
        
        node.prefix_info = prefix_info
        node.is_terminal = true
      end

      def traverse(string)
        node = @root
        
        string.each_char do |char|
          return nil unless node.children[char]
          node = node.children[char]
        end
        
        node
      end
    end
  end
end