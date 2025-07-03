# frozen_string_literal: true

module RubyUnits
  module Parser
    # Represents the result of parsing a unit expression
    class ParseResult
      attr_reader :scalar, :numerator, :denominator, :kind

      def initialize(scalar = 1, numerator = [], denominator = [], kind = nil)
        @scalar = scalar
        @numerator = numerator.freeze
        @denominator = denominator.freeze
        @kind = kind
      end

      def reset(scalar = 1, numerator = [], denominator = [], kind = nil)
        @scalar = scalar
        @numerator = numerator.freeze
        @denominator = denominator.freeze
        @kind = kind
        self
      end

      def to_s
        parts = []
        parts << @scalar.to_s unless @scalar == 1
        parts << @numerator.join('*') unless @numerator.empty?
        parts << "/#{@denominator.join('*')}" unless @denominator.empty?
        parts.join(' ')
      end

      def inspect
        "#<ParseResult scalar=#{@scalar} numerator=#{@numerator.inspect} denominator=#{@denominator.inspect}>"
      end

      def ==(other)
        other.is_a?(ParseResult) &&
          @scalar == other.scalar &&
          @numerator == other.numerator &&
          @denominator == other.denominator
      end

      # Convert to Unit object
      def to_unit
        unit_parts = []
        unit_parts << @scalar.to_s unless @scalar == 1
        unit_parts << @numerator.join('*') unless @numerator.empty?
        unit_parts << "/#{@denominator.join('*')}" unless @denominator.empty?
        
        unit_string = unit_parts.join(' ')
        unit_string = "1" if unit_string.empty?
        
        RubyUnits::Unit.new(unit_string)
      end
    end
  end
end