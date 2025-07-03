# frozen_string_literal: true

require_relative 'token'
require_relative 'parse_error'

module RubyUnits
  module Parser
    # High-performance tokenizer using finite state automaton
    class Tokenizer
      # Pre-allocated token pool for performance
      TOKEN_POOL_SIZE = 1000
      TOKEN_POOL = ::Array.new(TOKEN_POOL_SIZE) { Token.new(:unknown, "") }
      
      def initialize
        @token_index = 0
        @position = 0
        @input = ""
        @tokens = []
      end

      def tokenize(input)
        @input = input.to_s
        @position = 0
        @tokens = []
        @token_index = 0

        return [create_token(TokenType::EOF, "", 0)] if @input.empty?

        while @position < @input.length
          char = @input[@position]
          
          case char
          when /\s/
            skip_whitespace
          when /\d/
            parse_number
          when /[a-zA-Z°'"$%]/
            parse_unit_or_prefix
          when '*', '/', '^'
            @tokens << create_token(TokenType::OPERATOR, char, @position)
            @position += 1
          when '('
            @tokens << create_token(TokenType::LPAREN, char, @position)
            @position += 1
          when ')'
            @tokens << create_token(TokenType::RPAREN, char, @position)
            @position += 1
          when '+', '-'
            # Could be part of a number or an operator
            if looks_like_number_sign?
              parse_number
            else
              @tokens << create_token(TokenType::OPERATOR, char, @position)
              @position += 1
            end
          when ':'
            # Time format like 12:34:56
            if looks_like_time_format?
              parse_time_format
            else
              @position += 1 # Skip unknown character
            end
          when ','
            # Thousands separator in numbers
            if looks_like_thousands_separator?
              parse_number
            else
              @position += 1 # Skip unknown character
            end
          else
            @position += 1 # Skip unknown character
          end
        end

        @tokens << create_token(TokenType::EOF, "", @position)
        @tokens
      end

      private

      def create_token(type, value, position)
        if @token_index < TOKEN_POOL_SIZE
          token = TOKEN_POOL[@token_index]
          token.reset(type, value, position)
          @token_index += 1
          token
        else
          Token.new(type, value, position)
        end
      end

      def skip_whitespace
        while @position < @input.length && @input[@position] =~ /\s/
          @position += 1
        end
      end

      def parse_number
        start_pos = @position
        number_str = ""

        # Handle sign
        if @input[@position] =~ /[+-]/
          number_str += @input[@position]
          @position += 1
        end

        # Handle various number formats
        if looks_like_rational?
          number_str += parse_rational_part
        elsif looks_like_complex?
          number_str += parse_complex_part
        elsif looks_like_scientific?
          number_str += parse_scientific_part
        else
          number_str += parse_decimal_part
        end

        @tokens << create_token(TokenType::NUMBER, number_str, start_pos)
      end

      def parse_decimal_part
        result = ""
        
        # Integer part
        while @position < @input.length && @input[@position] =~ /\d/
          result += @input[@position]
          @position += 1
        end

        # Handle thousands separators
        if @position < @input.length && @input[@position] == ','
          while @position < @input.length && (@input[@position] =~ /[\d,]/)
            result += @input[@position] unless @input[@position] == ','
            @position += 1
          end
        end

        # Decimal part
        if @position < @input.length && @input[@position] == '.'
          result += @input[@position]
          @position += 1
          
          while @position < @input.length && @input[@position] =~ /\d/
            result += @input[@position]
            @position += 1
          end
        end

        result
      end

      def parse_scientific_part
        result = parse_decimal_part
        
        # Scientific notation
        if @position < @input.length && @input[@position] =~ /[eE]/
          result += @input[@position]
          @position += 1
          
          # Optional sign
          if @position < @input.length && @input[@position] =~ /[+-]/
            result += @input[@position]
            @position += 1
          end
          
          # Exponent digits
          while @position < @input.length && @input[@position] =~ /\d/
            result += @input[@position]
            @position += 1
          end
        end

        result
      end

      def parse_rational_part
        result = ""
        
        # Handle improper fractions like "1 2/3"
        if @position < @input.length && @input[@position] =~ /\d/
          # Parse whole number part
          while @position < @input.length && @input[@position] =~ /\d/
            result += @input[@position]
            @position += 1
          end
          
          # Check for space before fraction
          if @position < @input.length && @input[@position] == ' '
            # Look ahead to see if this is a fraction
            next_pos = @position + 1
            while next_pos < @input.length && @input[next_pos] =~ /\d/
              next_pos += 1
            end
            
            if next_pos < @input.length && @input[next_pos] == '/'
              result += " "
              @position += 1
            end
          end
        end

        # Parse numerator
        while @position < @input.length && @input[@position] =~ /\d/
          result += @input[@position]
          @position += 1
        end

        # Parse slash
        if @position < @input.length && @input[@position] == '/'
          result += @input[@position]
          @position += 1
          
          # Parse denominator
          while @position < @input.length && @input[@position] =~ /\d/
            result += @input[@position]
            @position += 1
          end
        end

        result
      end

      def parse_complex_part
        result = ""
        
        # Real part (optional)
        if @input[@position] =~ /\d/
          result += parse_decimal_part
        end

        # Imaginary part
        if @position < @input.length && @input[@position] =~ /[+-]/
          result += @input[@position]
          @position += 1
        end

        # Parse imaginary coefficient
        while @position < @input.length && @input[@position] =~ /\d/
          result += @input[@position]
          @position += 1
        end

        # Parse 'i'
        if @position < @input.length && @input[@position] == 'i'
          result += @input[@position]
          @position += 1
        end

        result
      end

      def parse_time_format
        # This is called when we encounter a ':' character
        # We need to look for the pattern HH:MM or HH:MM:SS
        # Since this is complex, for now just skip the ':' and let normal parsing handle it
        @position += 1 # Skip the ':'
      end

      def parse_unit_or_prefix
        start_pos = @position
        result = ""

        # Handle special symbols
        case @input[@position]
        when '°'
          result += @input[@position]
          @position += 1
          # Look for C or F
          if @position < @input.length && @input[@position] =~ /[CF]/
            result += @input[@position]
            @position += 1
          end
        when "'"
          result = "'"
          @position += 1
        when '"'
          result = '"'
          @position += 1
        when '$'
          result = "$"
          @position += 1
        when '%'
          result = "%"
          @position += 1
        else
          # Parse regular unit/prefix name
          while @position < @input.length && @input[@position] =~ /[a-zA-Z0-9_-]/
            result += @input[@position]
            @position += 1
          end
        end

        @tokens << create_token(TokenType::UNIT, result, start_pos)
      end

      # Helper methods for lookahead
      def looks_like_number_sign?
        return false if @position + 1 >= @input.length
        @input[@position + 1] =~ /\d/
      end

      def looks_like_time_format?
        # Look backward for digits and forward for digits
        return false if @position == 0 || @position + 1 >= @input.length
        @input[@position - 1] =~ /\d/ && @input[@position + 1] =~ /\d/
      end

      def looks_like_thousands_separator?
        return false if @position == 0 || @position + 1 >= @input.length
        @input[@position - 1] =~ /\d/ && @input[@position + 1] =~ /\d/
      end

      def looks_like_rational?
        # Look ahead for pattern like "1/2" or "1 2/3"
        pos = @position + 1
        pos += 1 while pos < @input.length && @input[pos] =~ /\d/
        
        # Check for space then numerator/denominator
        if pos < @input.length && @input[pos] == ' '
          pos += 1
          pos += 1 while pos < @input.length && @input[pos] =~ /\d/
        end
        
        pos < @input.length && @input[pos] == '/'
      end

      def looks_like_complex?
        # Look ahead for pattern like "1+2i" or "1i"
        pos = @position + 1
        pos += 1 while pos < @input.length && @input[pos] =~ /\d/
        
        return true if pos < @input.length && @input[pos] == 'i'
        
        # Check for +/- followed by more digits and i
        if pos < @input.length && @input[pos] =~ /[+-]/
          pos += 1
          pos += 1 while pos < @input.length && @input[pos] =~ /\d/
          pos < @input.length && @input[pos] == 'i'
        else
          false
        end
      end

      def looks_like_scientific?
        # Look ahead for pattern like "1e5" or "1E-5"
        pos = @position + 1
        pos += 1 while pos < @input.length && @input[pos] =~ /\d/
        
        # Check for decimal point
        if pos < @input.length && @input[pos] == '.'
          pos += 1
          pos += 1 while pos < @input.length && @input[pos] =~ /\d/
        end
        
        # Check for E/e
        if pos < @input.length && @input[pos] =~ /[eE]/
          pos += 1
          pos += 1 if pos < @input.length && @input[pos] =~ /[+-]/
          pos < @input.length && @input[pos] =~ /\d/
        else
          false
        end
      end
    end
  end
end