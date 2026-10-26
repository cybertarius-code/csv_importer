# frozen_string_literal: true

require 'bigdecimal'
require 'date'

module CsvImporter
  # Registro de conversores. Cada uno recibe un String y devuelve el valor
  # convertido, o lanza ArgumentError si no es válido.
  module Types
    TRUTHY = %w[true 1 yes si sí].freeze
    FALSY = %w[false 0 no].freeze

    @casters = {
      string: lambda(&:to_s),
      integer: ->(value) { Integer(value, 10) },
      decimal: ->(value) { BigDecimal(value) },
      date: ->(value) { Date.iso8601(value) },
      boolean: lambda do |value|
        normalized = value.to_s.downcase

        if TRUTHY.include?(normalized) then true
        elsif FALSY.include?(normalized) then false
        else raise ArgumentError, "valor booleano inválido: #{value.inspect}"
        end
      end
    }

    class << self
      # Permite a quien use la gema añadir sus propios tipos
      def register(name, &caster)
        @casters[name.to_sym] = caster
      end

      def fetch(type)
        @casters.fetch(type.to_sym) do
          raise ArgumentError, "Tipo desconocido: #{type.inspect}. Disponibles: #{@casters.keys.join(', ')}"
        end
      end
    end
  end
end
