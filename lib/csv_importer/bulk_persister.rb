# frozen_string_literal: true

module CsvImporter
  # Guarda un lote con una sola sentencia (insert_all / upsert_all).
  # Rápido, pero NO ejecuta callbacks y valida solo con los atributos de la fila.
  class BulkPersister
    include Transactional

    def initialize(model, find_by: [])
      @model = model
      @find_by = Array(find_by)
      verify_unique_index!
    end

    def persist(rows)
      validated = rows.map { |line, attributes| [line, attributes, validation_error(attributes)] }
      valid = validated.select { |_line, _attributes, error| error.nil? }.map { |_line, attributes, _error| attributes }
      existing = existing_keys(valid)

      write(valid)
      classify(validated, existing)
    end

    private

    # Sin un índice único, upsert_all no puede resolver conflictos
    # (y dos importaciones concurrentes podrían duplicar registros).
    def verify_unique_index!
      return if @find_by.empty?

      unique = @model.connection.indexes(@model.table_name).any? do |index|
        index.unique && index.where.nil? && Array(index.columns).map(&:to_sym).sort == @find_by.sort
      end
      return if unique

      raise ConfigurationError,
            "El modo masivo necesita un índice único en #{@find_by.join(', ')} de #{@model.table_name}"
    end

    def validation_error(attributes)
      record = @model.new(attributes)
      record.valid? ? nil : record.errors.full_messages.to_sentence
    end

    # Una consulta por lote: qué claves ya existen en la base de datos
    def existing_keys(attributes_list)
      return Set.new if @find_by.empty? || attributes_list.empty?

      conditions = @find_by.to_h do |key|
        [key, attributes_list.filter_map { |attributes| attributes[key] }.uniq]
      end

      @model.where(conditions).pluck(*@find_by).to_set { |value| value.is_a?(Array) ? value : [value] }
    end

    def write(attributes_list)
      return if attributes_list.empty?

      if @find_by.empty?
        @model.insert_all(attributes_list)
      else
        @model.upsert_all(deduplicate(attributes_list), **upsert_options)
      end
    end

    # Una misma fila no puede aparecer dos veces en un upsert (PostgreSQL lo rechaza).
    # Gana la última, igual que en el modo normal.
    def deduplicate(attributes_list)
      with_key, without_key = attributes_list.partition { |attributes| key_of(attributes) }

      with_key.reverse.uniq { |attributes| key_of(attributes) }.reverse + without_key
    end

    def upsert_options
      @model.connection.supports_insert_conflict_target? ? { unique_by: @find_by } : {}
    end

    def key_of(attributes)
      return if @find_by.empty?

      key = attributes.values_at(*@find_by)
      key unless key.any?(&:nil?)
    end

    def classify(validated, existing)
      seen = Set.new

      validated.map do |line, attributes, error|
        next Outcome.new(line: line, status: :invalid, message: error) if error

        Outcome.new(line: line, status: status_for(attributes, existing, seen))
      end
    end

    # Primera aparición de una clave: creada o actualizada según exista ya.
    # Repeticiones dentro del lote: actualizada.
    def status_for(attributes, existing, seen)
      key = key_of(attributes)
      return :created if key.nil?
      return :updated unless seen.add?(key)

      existing.include?(key) ? :updated : :created
    end
  end
end
