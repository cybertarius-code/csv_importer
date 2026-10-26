# frozen_string_literal: true

module CsvImporter
  # Guarda fila a fila con ActiveRecord: respeta validaciones y callbacks.
  class RecordPersister
    include Transactional

    def initialize(model, find_by: [])
      @model = model
      @find_by = Array(find_by)
      @cache = nil
    end

    def persist(rows)
      preload(rows.map(&:last))
      rows.map { |line, attributes| persist_row(line, attributes) }
    end

    private

    def persist_row(line, attributes)
      record = find_existing(attributes) || @model.new
      record.assign_attributes(attributes)
      record.save
      remember(record)

      if record.errors.empty?
        Outcome.new(line: line, status: record.previously_new_record? ? :created : :updated)
      else
        Outcome.new(line: line, status: :invalid, message: record.errors.full_messages.to_sentence)
      end
    end

    # Carga de una vez los registros existentes de un lote
    def preload(attributes_list)
      @cache = nil
      return unless @find_by.size == 1 # con claves compuestas se busca fila a fila

      key = @find_by.first
      values = attributes_list.filter_map { |attributes| attributes[key] }.uniq
      @cache = values.empty? ? {} : @model.where(key => values).index_by { |record| record[key] }
    end

    def find_existing(attributes)
      return if @find_by.empty?
      return if @find_by.any? { |key| attributes[key].nil? }
      return @cache[attributes[@find_by.first]] if @cache

      @model.find_by(attributes.slice(*@find_by))
    end

    # Una clave repetida dentro del lote actualiza el registro en vez de duplicarlo
    def remember(record)
      return unless @cache && record.errors.empty?

      @cache[record[@find_by.first]] = record
    end
  end
end
