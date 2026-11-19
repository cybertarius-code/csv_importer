# frozen_string_literal: true

module CsvImporter
  # Clase base del DSL. Cada importador hereda de ella y declara su configuración:
  #
  #   class UserImporter < CsvImporter::Base
  #     model User
  #     csv col_sep: ";", encoding: "Windows-1252"
  #     column :email, header: "Correo", required: true
  #     find_by :email
  #   end
  #
  #   UserImporter.new("usuarios.csv", defaults: { team_id: 3 }).call
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

      # Formato del archivo: col_sep:, encoding:, headers:, skip_lines:
      def csv(**options)
        definition.csv_options = options
        definition.csv_options
      end

      # Gancho por fila: recibe (attributes, raw_row) tras convertir la fila
      def after_map(callable = nil, &block)
        definition.add_after_map(callable || block)
      end
    end

    # Las opciones de cada ejecución; el formato y las columnas son de la clase.
    def initialize(file_path, atomic: false, bulk: false, batch_size: Importer::DEFAULT_BATCH_SIZE, # rubocop:disable Metrics/ParameterLists
                   defaults: {}, after_map: nil)
      @file_path = file_path
      @atomic = atomic
      @bulk = bulk
      @batch_size = batch_size
      @defaults = defaults
      @after_map = after_map
      self.class.definition.validate!
    end

    def call
      definition = self.class.definition

      Importer.new(@file_path, definition.model, **importer_options(definition)).call
    end

    private

    # Los ganchos de la clase se ejecutan antes que el de la llamada
    def importer_options(definition)
      {
        columns: definition.columns, find_by: definition.find_by_keys, csv: definition.csv_options,
        atomic: @atomic, bulk: @bulk, batch_size: @batch_size,
        defaults: @defaults, after_map: [*definition.after_map_hooks, *@after_map]
      }
    end
  end
end
