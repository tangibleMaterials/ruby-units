# frozen_string_literal: true

require_relative 'parser/token'
require_relative 'parser/tokenizer'
require_relative 'parser/unit_trie'
require_relative 'parser/parser'
require_relative 'parser/parse_result'
require_relative 'parser/parse_error'

module RubyUnits
  module Parser
    # Main parser instance (singleton for performance)
    @parser_instance = nil

    # Parse a unit expression using the new parser
    def self.parse(input)
      @parser_instance ||= Parser.new
      @parser_instance.parse(input)
    end

    # Clear the parser instance (for testing)
    def self.reset!
      @parser_instance = nil
    end
  end
end