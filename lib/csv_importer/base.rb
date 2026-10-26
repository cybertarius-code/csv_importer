# frozen_string_literal: true

module CsvImporter
  class Base
    # aquí dentro se definen métodos DE CLASE
    class << self
      # Una configuración por clase, creada la primera vez que se pide
      def definition
        @definition ||= Definition.new
      end

      # Se ejecuta cada vez que alguien hereda de esta clase.
      # El hijo recibe una COPIA: puede ampliarla sin alterar al padre.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@definition, definition.dup)
      end

      # Sin argumento lee; con argumento escribe (como `table_name` en Rails)
      def model(klass = nil)
        definition.model = klass if klass
        definition.model
      end

      def column(attribute, **options)
        definition.add_column(attribute, **options)
      end

      def find_by(*keys)
        definition.find_by_keys = keys.map(&:to_sym)
      end
    end

    def initialize(file_path, atomic: false, bulk: false, batch_size: Importer::DEFAULT_BATCH_SIZE)
      @file_path = file_path
      @atomic = atomic
      @bulk = bulk
      @batch_size = batch_size
      self.class.definition.validate!
    end

    def call
      definition = self.class.definition

      Importer.new(
        @file_path, definition.model,
        columns: definition.columns,
        find_by: definition.find_by_keys,
        atomic: @atomic,
        bulk: @bulk,
        batch_size: @batch_size
      ).call
    end
  end
end
