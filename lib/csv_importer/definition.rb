# frozen_string_literal: true

module CsvImporter
  # Guarda lo que el DSL declara para una clase importadora.
  class Definition
    attr_accessor :model, :find_by_keys
    attr_reader :columns, :csv_options, :after_map_hooks

    def initialize
      @model = nil
      @columns = []
      @find_by_keys = []
      @csv_options = {}
      @after_map_hooks = []
    end

    # dup es superficial: sin esto, padre e hijo compartirían los mismos arrays y hashes
    def initialize_copy(source)
      super
      @columns = source.columns.dup
      @find_by_keys = source.find_by_keys.dup
      @csv_options = source.csv_options.dup
      @after_map_hooks = source.after_map_hooks.dup
    end

    def add_column(attribute, **options)
      column = Column.new(attribute, **options)
      @columns.reject! { |existing| existing.attribute == column.attribute }
      @columns << column
    end

    # Una subclase puede cambiar solo algunas opciones: se mezclan con las del padre
    def csv_options=(options)
      @csv_options = Parser.validate_options!(csv_options.merge(options.transform_keys(&:to_sym)))
    end

    def add_after_map(hook)
      raise ConfigurationError, '`after_map` necesita un bloque o un objeto con `call`' unless hook.respond_to?(:call)

      @after_map_hooks << hook
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
