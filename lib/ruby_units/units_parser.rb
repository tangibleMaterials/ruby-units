# frozen_string_literal: true

require_relative '../../ext/units_parser/units_parser'

module RubyUnits
  # Ragel-based parser integration
  module Parser
    # ParseResult class to match the interface expected by ruby-units
    class ParseResult
      attr_reader :scalar, :numerator, :denominator

      def initialize(scalar, numerator, denominator)
        @scalar = scalar
        @numerator = numerator
        @denominator = denominator
      end
    end

    # ParseError class for compatibility
    class ParseError < StandardError
    end

    # Convert unit alias to canonical unit name and handle exponents/prefixes
    def self.canonicalize_unit(unit_string)
      # Handle exponents (e.g., "s^2" → ["s", "s"] for repeated units)
      base_unit = unit_string.sub(/\^.*$/, '')
      exponent = unit_string[/\^(.+)$/, 1]
      
      # Convert exponent to integer, default to 1
      exp_count = exponent ? exponent.to_i : 1
      
      # Look up the canonical name in the unit map
      canonical = RubyUnits::Unit.unit_map[base_unit]
      
      if canonical
        # Direct unit mapping found
        canonical_unit = canonical
      else
        # Check if it's a prefixed unit (e.g., "km" = "k" + "m")
        prefix_found = false
        RubyUnits::Unit.prefix_map.each do |prefix_alias, prefix_canonical|
          if base_unit.start_with?(prefix_alias)
            unit_part = base_unit[prefix_alias.length..-1]
            unit_canonical = RubyUnits::Unit.unit_map[unit_part]
            if unit_canonical
              # Return array of [prefix, unit] for prefixed units
              canonical_unit = [prefix_canonical, unit_canonical]
              prefix_found = true
              break
            end
          end
        end
        
        unless prefix_found
          # If not found, assume it's already canonical or add brackets
          canonical_unit = base_unit.start_with?('<') ? base_unit : "<#{base_unit}>"
        end
      end
      
      # Handle exponents by repeating the unit
      if exp_count > 1
        if canonical_unit.is_a?(Array)
          # For prefixed units, repeat the entire array
          ::Array.new(exp_count) { canonical_unit }.flatten
        else
          # For simple units, repeat the unit
          ::Array.new(exp_count, canonical_unit)
        end
      elsif canonical_unit.is_a?(Array)
        canonical_unit
      else
        [canonical_unit]
      end
    end

    # Main parsing interface
    def self.parse(input)
      result = RubyUnits::UnitsParser.parse(input.to_s)
      
      if result["success"]
        # Convert scalar string to appropriate numeric type
        scalar_str = result["scalar"]
        scalar = case scalar_str
                when /^\s*$/, "1" then 1
                when /^[+-]?\d+$/ then scalar_str.to_i
                when /^[+-]?\d*\.?\d+([eE][+-]?\d+)?$/ then scalar_str.to_f
                when /^[+-]?\d*\.?\d*[+-]\d*\.?\d*i$/ then Complex(scalar_str)
                when %r{^[+-]?\d*\.?\d*\s*/\s*[+-]?\d*\.?\d*$} then Rational(scalar_str)
                else 
                  begin
                    eval(scalar_str) # For complex expressions
                  rescue
                    1
                  end
                end
        
        # Process units arrays and convert to canonical unit names
        numerator = result["numerator"] || []
        denominator = result["denominator"] || []
        
        # Convert unit aliases to canonical names (e.g., "kg" → ["<kilo>", "<gram>"])
        numerator = numerator.flat_map { |unit| canonicalize_unit(unit) }
        denominator = denominator.flat_map { |unit| canonicalize_unit(unit) }
        
        ParseResult.new(scalar, numerator, denominator)
      else
        raise ParseError, result["error"] || "Parse failed"
      end
    end
  end
end