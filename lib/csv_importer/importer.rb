# frozen_string_literal: true

module CsvImporter
  class Importer
    DEFAULT_BATCH_SIZE = 1_000

    def initialize(file_path, model, columns:, atomic: false, find_by: [], bulk: false,
                   batch_size: DEFAULT_BATCH_SIZE,
                   parser: Parser.new(file_path),
                   mapper: RowMapper.new(columns),
                   persister: (bulk ? BulkPersister : RecordPersister).new(model, find_by: find_by))
      @atomic = atomic
      @batch_size = batch_size
      @parser = parser
      @mapper = mapper
      @persister = persister
    end

    def call
      validate_headers!

      @atomic ? import_atomically : import_rows
    end

    private

    def import_rows
      Result.new.tap do |result|
        @parser.each_row.each_slice(@batch_size) { |batch| import_batch(batch, result) }
      end
    end

    def import_batch(batch, result)
      rows = map_rows(batch, result)
      @persister.persist(rows).each { |outcome| record_outcome(outcome, result) }
    end

    # Convierte las filas del lote; las que no se pueden convertir
    # se reportan como error y se descartan.
    def map_rows(batch, result)
      batch.filter_map do |line, raw_row|
        [line, @mapper.call(raw_row)]
      rescue ConversionError => e
        result.add_error(line: line, message: e.message)
        nil
      end
    end

    def record_outcome(outcome, result)
      case outcome.status
      when :created then result.add_created
      when :updated then result.add_updated
      else result.add_error(line: outcome.line, message: outcome.message)
      end
    end

    def import_atomically
      result = nil

      @persister.atomically do
        result = import_rows
        result.success?
      end

      result.rollback! unless result.success?
      result
    end

    def validate_headers!
      missing = @mapper.headers - @parser.headers
      return if missing.empty?

      raise InvalidHeaderError, "Faltan columnas en el CSV: #{missing.join(', ')}"
    end
  end
end
