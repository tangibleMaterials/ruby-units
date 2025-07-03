# frozen_string_literal: true

module RubyUnits
  module Parser
    # Error raised when parsing fails
    class ParseError < StandardError
      attr_reader :position, :expected, :actual

      def initialize(message, position = nil, expected = nil, actual = nil)
        super(message)
        @position = position
        @expected = expected
        @actual = actual
      end

      def to_s
        if @position
          "#{super} at position #{@position}"
        else
          super
        end
      end
    end
  end
end