# frozen_string_literal: true

module CsvImporter
  # Guarda lo que el DSL declara para una clase importadora.
  class Definition
    attr_accessor :model, :find_by_keys
    attr_reader :columns

    def initialize
      @model = nil
      @columns = []
      @find_by_keys = []
    end

    # dup es superficial: sin esto, padre e hijo compartirían el mismo array
    def initialize_copy(source)
      super
      @columns = source.columns.dup
      @find_by_keys = source.find_by_keys.dup
    end

    def add_column(attribute, **options)
      column = Column.new(attribute, **options)
      @columns.reject! { |existing| existing.attribute == column.attribute }
      @columns << column
    end

    def validate!
      raise ConfigurationError, 'Falta declarar `model`' if model.nil?
      raise ConfigurationError, 'Declara al menos una `column`' if columns.empty?

      unknown = find_by_keys - columns.map(&:attribute)
      return if unknown.empty?

      raise ConfigurationError, "find_by usa atributos que no son columnas: #{unknown.join(', ')}"
    end
  end
end
