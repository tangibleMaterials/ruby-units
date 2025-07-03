# frozen_string_literal: true

require_relative 'tokenizer'
require_relative 'unit_trie'
require_relative 'parse_result'
require_relative 'parse_error'

module RubyUnits
  module Parser
    # High-performance recursive descent parser for unit expressions
    class Parser
      # Result pool for memory efficiency
      RESULT_POOL_SIZE = 100
      RESULT_POOL = ::Array.new(RESULT_POOL_SIZE) { ParseResult.new }

      def initialize
        @tokenizer = Tokenizer.new
        @unit_trie = UnitTrie.new
        @tokens = []
        @position = 0
        @current_token = nil
        @result_index = 0
      end

      def parse(input)
        @tokens = @tokenizer.tokenize(input)
        @position = 0
        @current_token = @tokens[0]
        @result_index = 0

        result = parse_expression
        expect_token(TokenType::EOF)
        result
      end

      private

      def parse_expression
        left = parse_term

        while current_token_type == TokenType::OPERATOR && 
              ['*', '/'].include?(current_token_value)
          operator = current_token_value
          consume_token
          right = parse_term
          left = combine_results(left, right, operator)
        end

        left
      end

      def parse_term
        base = parse_factor

        if current_token_type == TokenType::OPERATOR && current_token_value == '^'
          consume_token
          exponent = parse_exponent
          base = apply_exponent(base, exponent)
        end

        base
      end

      def parse_factor
        case current_token_type
        when TokenType::NUMBER
          scalar = parse_number
          
          # Check if followed by a unit
          if current_token_type == TokenType::UNIT
            unit_result = parse_unit
            unit_result.reset(scalar * unit_result.scalar, 
                             unit_result.numerator, 
                             unit_result.denominator)
            unit_result
          else
            create_result(scalar, [], [])
          end
        when TokenType::UNIT
          parse_unit
        when TokenType::LPAREN
          consume_token
          result = parse_expression
          expect_token(TokenType::RPAREN)
          result
        else
          raise ParseError.new("Unexpected token: #{current_token_value}", 
                              @current_token&.position)
        end
      end

      def parse_number
        number_str = current_token_value
        consume_token
        
        # Parse various number formats
        if number_str.include?('/')
          parse_rational(number_str)
        elsif number_str.include?('i')
          parse_complex(number_str)
        elsif number_str.include?(':')
          parse_time_format(number_str)
        elsif number_str.include?('e') || number_str.include?('E')
          parse_scientific(number_str)
        else
          parse_decimal(number_str)
        end
      end

      def parse_rational(number_str)
        if number_str.include?(' ')
          # Mixed number like "1 2/3"
          parts = number_str.split(' ')
          whole = parts[0].to_f
          fraction_parts = parts[1].split('/')
          numerator = fraction_parts[0].to_f
          denominator = fraction_parts[1].to_f
          whole + (numerator / denominator)
        else
          # Simple fraction like "2/3"
          parts = number_str.split('/')
          parts[0].to_f / parts[1].to_f
        end
      end

      def parse_complex(number_str)
        # For now, just parse as regular number (real part)
        # Full complex number support would require more work
        if number_str.end_with?('i')
          # Pure imaginary number
          real_part = number_str[0...-1]
          real_part.empty? ? 1.0 : real_part.to_f
        else
          number_str.to_f
        end
      end

      def parse_time_format(number_str)
        # Parse time format like "12:34:56" as seconds
        parts = number_str.split(':')
        case parts.length
        when 2
          parts[0].to_f * 3600 + parts[1].to_f * 60
        when 3
          parts[0].to_f * 3600 + parts[1].to_f * 60 + parts[2].to_f
        else
          number_str.to_f
        end
      end

      def parse_scientific(number_str)
        number_str.to_f
      end

      def parse_decimal(number_str)
        number_str.to_f
      end

      def parse_unit
        unit_name = current_token_value
        consume_token

        # Handle special unit conversions
        unit_name = convert_special_units(unit_name)

        # Look up unit with possible prefix
        prefix_info, unit_info = @unit_trie.parse_unit_with_prefix(unit_name)

        unless unit_info
          raise ParseError.new("Unknown unit: #{unit_name}", 
                              @current_token&.position)
        end

        # Keep prefix separate like legacy parser for proper unit conversion
        scalar = 1.0
        numerator = []
        
        if prefix_info
          # Add prefix to numerator like legacy parser
          numerator << prefix_info[:name]
        end
        
        # Get base unit name (keep brackets for compatibility)
        base_unit = unit_info.name
        numerator << base_unit

        create_result(scalar, numerator, [])
      end

      def parse_exponent
        exponent_str = current_token_value
        consume_token
        
        # Handle negative exponents
        if exponent_str.start_with?('-')
          -exponent_str[1..-1].to_i
        elsif exponent_str.start_with?('+')
          exponent_str[1..-1].to_i
        else
          exponent_str.to_i
        end
      end

      def combine_results(left, right, operator)
        case operator
        when '*'
          create_result(
            left.scalar * right.scalar,
            left.numerator + right.numerator,
            left.denominator + right.denominator
          )
        when '/'
          create_result(
            left.scalar / right.scalar,
            left.numerator + right.denominator,
            left.denominator + right.numerator
          )
        else
          raise ParseError.new("Unknown operator: #{operator}")
        end
      end

      def apply_exponent(base, exponent)
        if exponent > 0
          # Positive exponent: multiply units but keep scalar unchanged for unit expressions
          numerator = base.numerator * exponent
          denominator = base.denominator * exponent
          scalar = base.scalar # Don't apply exponent to scalar for unit expressions
        elsif exponent < 0
          # Negative exponent: flip and multiply
          numerator = base.denominator * (-exponent)
          denominator = base.numerator * (-exponent)
          scalar = base.scalar # Don't apply exponent to scalar for unit expressions
        else
          # Zero exponent: dimensionless
          numerator = []
          denominator = []
          scalar = base.scalar # Keep original scalar
        end

        create_result(scalar, numerator, denominator)
      end

      def convert_special_units(unit_name)
        # Convert special symbols to standard unit names
        case unit_name
        when "'"
          'foot'
        when '"'
          'inch'
        when '$'
          'USD'
        when '%'
          '%'
        when '°C'
          'degC'
        when '°F'
          'degF'
        when /^°([CF])$/
          "deg#{$1}"
        else
          unit_name
        end
      end

      def create_result(scalar, numerator, denominator)
        if @result_index < RESULT_POOL_SIZE
          result = RESULT_POOL[@result_index]
          result.reset(scalar, numerator, denominator)
          @result_index += 1
          result
        else
          ParseResult.new(scalar, numerator, denominator)
        end
      end

      def current_token_type
        @current_token&.type
      end

      def current_token_value
        @current_token&.value
      end

      def consume_token
        @position += 1
        @current_token = @tokens[@position]
        @current_token
      end

      def expect_token(expected_type)
        if current_token_type != expected_type
          raise ParseError.new("Expected #{expected_type}, got #{current_token_type}", 
                              @current_token&.position)
        end
        consume_token
      end
    end
  end
end