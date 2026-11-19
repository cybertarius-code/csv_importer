# frozen_string_literal: true

require 'csv'

module CsvImporter
  # Única responsabilidad: leer un archivo CSV y entregar sus filas.
  #
  #   Parser.new(path)                                        # comas, UTF-8 y fila de títulos
  #   Parser.new(path, col_sep: ';', encoding: 'Windows-1252', skip_lines: 2)
  #   Parser.new(path, col_sep: '|', headers: %w[fecha concepto importe]) # sin fila de títulos
  class Parser
    # "bom|utf-8" tolera el BOM que añade Excel al exportar CSV
    ENCODING = 'bom|utf-8'
    OPTIONS = %i[col_sep encoding headers skip_lines].freeze

    class << self
      # Falla al declarar, no al importar, si las opciones no tienen sentido
      def validate_options!(options)
        unknown = options.keys.map(&:to_sym) - OPTIONS
        raise ConfigurationError, "Opciones de CSV desconocidas: #{unknown.join(', ')}" if unknown.any?

        new(nil, **options)
        options
      end
    end

    attr_reader :encoding

    def initialize(file_path, col_sep: ',', encoding: ENCODING, headers: nil, skip_lines: 0)
      @file_path = file_path
      @col_sep = col_sep
      @encoding = normalize_encoding(encoding)
      @given_headers = normalize_headers(headers)
      @skip_lines = normalize_skip_lines(skip_lines)
    end

    def headers
      @headers ||= @given_headers || read { |csv| shift(csv) } || []
    end

    # Entrega (número de línea, hash header => valor).
    # El número de línea es el del archivo: cuenta las líneas saltadas y la de títulos.
    def each_row
      return enum_for(:each_row) unless block_given?

      read(headers: @given_headers || true) do |csv|
        line = first_data_line
        while (row = shift(csv))
          yield line, row.to_h
          line += 1
        end
      end
    end

    private

    def first_data_line
      @skip_lines + (@given_headers ? 1 : 2)
    end

    def read(**csv_options)
      File.open(@file_path, "r:#{@encoding}") do |io|
        translating_errors { @skip_lines.times { io.gets } }
        yield CSV.new(io, col_sep: @col_sep, **csv_options)
      end
    end

    def shift(csv)
      translating_errors { csv.shift }
    end

    # Solo envuelve la lectura: los errores de quien consume las filas pasan tal cual
    def translating_errors
      yield
    rescue CSV::InvalidEncodingError => e
      raise InvalidFileError, "El archivo no está en #{external_encoding} (línea #{file_line(e)}). " \
                              'Indica su codificación con `encoding:`, por ejemplo "Windows-1252"'
    rescue CSV::MalformedCSVError => e
      raise InvalidFileError, "CSV mal formado en la línea #{file_line(e)}: #{e.message.sub(/ in line \d+\.\z/, '')}"
    rescue EncodingError => e
      raise InvalidFileError, "El archivo tiene caracteres que no existen en #{external_encoding}: #{e.message}"
    end

    # CSV numera desde donde empieza a leer, después de las líneas saltadas
    def file_line(error)
      error.line_number + @skip_lines
    end

    def external_encoding
      @encoding.split(':').first.delete_prefix('bom|').upcase
    end

    # "Windows-1252" se convierte a UTF-8 al leer ("Windows-1252:UTF-8"),
    # para que la aplicación siempre reciba texto en UTF-8.
    def normalize_encoding(encoding)
      external, internal, *rest = encoding.to_s.split(':')
      raise ConfigurationError, "Codificación inválida: #{encoding.inspect}" if external.nil? || rest.any?

      internal ||= 'UTF-8' unless find_encoding(external) == Encoding::UTF_8
      find_encoding(internal) if internal
      [external, internal].compact.join(':')
    end

    def find_encoding(name)
      Encoding.find(name.delete_prefix('bom|'))
    rescue ArgumentError
      raise ConfigurationError, "Codificación desconocida: #{name.inspect}"
    end

    def normalize_headers(headers)
      return if headers.nil?

      names = Array(headers).map(&:to_s)
      return names if headers.is_a?(Array) && names.any? && names.none?(&:empty?)

      raise ConfigurationError, '`headers:` debe ser una lista con el nombre de cada columna, en orden'
    end

    def normalize_skip_lines(skip_lines)
      return skip_lines if skip_lines.is_a?(Integer) && !skip_lines.negative?

      raise ConfigurationError, '`skip_lines:` debe ser un entero mayor o igual que 0'
    end
  end
end
