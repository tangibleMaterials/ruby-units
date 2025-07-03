# frozen_string_literal: true

module RubyUnits
  class << self
    attr_writer :configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  # Reset the configuration to the default values
  def self.reset
    @configuration = Configuration.new
  end

  # allow for optional configuration of RubyUnits
  #
  # Usage:
  #
  #     RubyUnits.configure do |config|
  #       config.separator = false
  #     end
  def self.configure
    yield configuration
  end

  # holds actual configuration values for RubyUnits
  class Configuration
    # Used to separate the scalar from the unit when generating output. A value
    # of `true` will insert a single space, and `false` will prevent adding a
    # space to the string representation of a unit.
    #
    # @!attribute [rw] separator
    #   @return [Boolean] whether to include a space between the scalar and the unit
    attr_reader :separator

    # The style of format to use by default when generating output. When set to `:exponential`, all units will be
    # represented in exponential notation instead of using a numerator and denominator.
    #
    # @!attribute [rw] format
    #   @return [Symbol] the format to use when generating output (:rational or :exponential) (default: :rational)
    attr_reader :format

    # Whether to use the new high-performance parser instead of the legacy regex-based parser
    #
    # @!attribute [rw] use_new_parser
    #   @return [Boolean] whether to use the new parser (default: false)
    attr_reader :use_new_parser

    # Enable compatibility mode that validates new parser results against legacy parser
    #
    # @!attribute [rw] compatibility_mode
    #   @return [Boolean] whether to enable compatibility mode (default: false)
    attr_reader :compatibility_mode

    # Size of the parser result cache
    #
    # @!attribute [rw] parser_cache_size
    #   @return [Integer] maximum number of cached parser results (default: 1000)
    attr_reader :parser_cache_size

    # Enable debug logging for the parser
    #
    # @!attribute [rw] parser_debug
    #   @return [Boolean] whether to enable parser debug logging (default: false)
    attr_reader :parser_debug

    def initialize
      self.format = :rational
      self.separator = true
      self.use_new_parser = false
      self.compatibility_mode = false
      self.parser_cache_size = 1000
      self.parser_debug = false
    end

    # Use a space for the separator to use when generating output.
    #
    # @param value [Boolean] whether to include a space between the scalar and the unit
    # @return [void]
    def separator=(value)
      raise ArgumentError, "configuration 'separator' may only be true or false" unless [true, false].include?(value)

      @separator = value ? " " : nil
    end

    # Set the format to use when generating output.
    # The `:rational` style will generate units string like `3 m/s^2` and the `:exponential` style will generate units
    # like `3 m*s^-2`.
    #
    # @param value [Symbol] the format to use when generating output (:rational or :exponential)
    # @return [void]
    def format=(value)
      raise ArgumentError, "configuration 'format' may only be :rational or :exponential" unless %i[rational exponential].include?(value)

      @format = value
    end

    # Enable or disable the new high-performance parser
    #
    # @param value [Boolean] whether to use the new parser
    # @return [void]
    def use_new_parser=(value)
      raise ArgumentError, "configuration 'use_new_parser' may only be true or false" unless [true, false].include?(value)

      @use_new_parser = value
    end

    # Enable or disable compatibility mode
    #
    # @param value [Boolean] whether to enable compatibility mode
    # @return [void]
    def compatibility_mode=(value)
      raise ArgumentError, "configuration 'compatibility_mode' may only be true or false" unless [true, false].include?(value)

      @compatibility_mode = value
    end

    # Set the parser cache size
    #
    # @param value [Integer] maximum number of cached parser results
    # @return [void]
    def parser_cache_size=(value)
      raise ArgumentError, "configuration 'parser_cache_size' must be a positive integer" unless value.is_a?(Integer) && value > 0

      @parser_cache_size = value
    end

    # Enable or disable parser debug logging
    #
    # @param value [Boolean] whether to enable parser debug logging
    # @return [void]
    def parser_debug=(value)
      raise ArgumentError, "configuration 'parser_debug' may only be true or false" unless [true, false].include?(value)

      @parser_debug = value
    end
  end
end
