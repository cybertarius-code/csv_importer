# frozen_string_literal: true

module CsvImporter
  # Traduce una fila cruda a atributos. Solo pasan las columnas declaradas.
  class RowMapper
    # Acepta Columns, o el hash { "header" => :atributo } de los pasos anteriores
    def initialize(columns)
      @columns = normalize(columns)
    end

    def headers
      @columns.map(&:header)
    end

    def call(raw_row)
      @columns.each_with_object({}) do |column, attributes|
        attributes[column.attribute] = column.extract(raw_row)
      end
    end

    private

    def normalize(columns)
      return columns unless columns.is_a?(Hash)

      columns.map { |header, attribute| Column.new(attribute, header: header) }
    end
  end
end
