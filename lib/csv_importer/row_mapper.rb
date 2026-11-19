# frozen_string_literal: true

module CsvImporter
  # Traduce una fila cruda a atributos. Solo pasan las columnas declaradas,
  # los valores fijos (`defaults`) y lo que añadan los ganchos `after_map`.
  class RowMapper
    # Acepta Columns, o el hash { "header" => :atributo } de los pasos anteriores
    def initialize(columns, defaults: {}, after_map: [])
      @columns = normalize(columns)
      @defaults = (defaults || {}).transform_keys(&:to_sym).freeze
      @hooks = Array(after_map)
      validate_hooks!
    end

    def headers
      @columns.map(&:header)
    end

    # Orden: columnas convertidas -> defaults (el CSV no puede sobrescribirlos) -> ganchos.
    # Un gancho puede modificar `attributes` en sitio o devolver un Hash nuevo.
    # Si lanza ConversionError, la fila se reporta como error.
    def call(raw_row)
      attributes = @columns.each_with_object({}) do |column, mapped|
        mapped[column.attribute] = column.extract(raw_row)
      end.merge(@defaults)

      @hooks.reduce(attributes) do |current, hook|
        returned = hook.call(current, raw_row)
        returned.is_a?(Hash) ? returned : current
      end
    end

    private

    def normalize(columns)
      return columns unless columns.is_a?(Hash)

      columns.map { |header, attribute| Column.new(attribute, header: header) }
    end

    def validate_hooks!
      return if @hooks.all? { |hook| hook.respond_to?(:call) }

      raise ConfigurationError, '`after_map` debe responder a `call(attributes, raw_row)`'
    end
  end
end
