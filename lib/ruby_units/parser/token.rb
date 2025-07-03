# frozen_string_literal: true

module RubyUnits
  module Parser
    # Token types for the parser
    module TokenType
      NUMBER = :number           # 123, 1.5, 1e-5, 1/2
      UNIT = :unit              # meter, kg, ft
      PREFIX = :prefix          # kilo, mega, micro
      OPERATOR = :operator      # *, /, ^
      LPAREN = :lparen         # (
      RPAREN = :rparen         # )
      WHITESPACE = :whitespace  # spaces, tabs
      EOF = :eof               # end of input
    end

    # Represents a token in the input stream
    class Token
      attr_reader :type, :value, :position

      def initialize(type, value, position = 0)
        @type = type
        @value = value.freeze
        @position = position
      end

      def reset(type, value, position = 0)
        @type = type
        @value = value.freeze
        @position = position
        self
      end

      def to_s
        "#{@type}:#{@value}"
      end

      def inspect
        "#<Token #{@type}:#{@value.inspect} @#{@position}>"
      end

      def ==(other)
        other.is_a?(Token) && 
          @type == other.type && 
          @value == other.value
      end
    end
  end
end