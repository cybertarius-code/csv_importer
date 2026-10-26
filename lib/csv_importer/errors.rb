# frozen_string_literal: true

module CsvImporter
  class Error < StandardError; end
  class InvalidHeaderError < Error; end
  class ConfigurationError < Error; end
  class ConversionError < Error; end
end
