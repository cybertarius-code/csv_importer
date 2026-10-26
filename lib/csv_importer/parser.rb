# frozen_string_literal: true

require 'csv'

module CsvImporter
  # Única responsabilidad: leer un archivo CSV y entregar sus filas.
  class Parser
    # "bom|utf-8" tolera el BOM que añade Excel al exportar CSV
    ENCODING = 'bom|utf-8'

    def initialize(file_path)
      @file_path = file_path
    end

    def headers
      @headers ||= CSV.foreach(@file_path, encoding: ENCODING).first || []
    end

    # Entrega (número de línea, hash header => valor)
    def each_row
      return enum_for(:each_row) unless block_given?

      CSV.foreach(@file_path, headers: true, encoding: ENCODING).with_index(2) do |row, line|
        yield line, row.to_h
      end
    end
  end
end
