# frozen_string_literal: true

module CsvImporter
  class Column
    attr_reader :attribute, :header

    def initialize(attribute, header: nil, type: nil, required: false, transform: nil)
      @attribute = attribute.to_sym
      @header = (header || attribute).to_s # por convención, el header se llama como el atributo
      @caster = Types.fetch(type) if type  # falla aquí si el tipo no existe
      @required = required
      @transform = transform
    end

    # Toma la fila cruda y devuelve el valor ya limpio y convertido
    def extract(raw_row)
      value = normalize(raw_row[header])

      if value.nil?
        raise ConversionError, "#{header}: no puede estar vacío" if @required

        return nil
      end

      value = @caster.call(value) if @caster
      value = @transform.call(value) if @transform
      value
    rescue ArgumentError, TypeError => e
      raise ConversionError, "#{header}: #{e.message}"
    end

    private

    # Quita espacios y trata la celda vacía como nil
    def normalize(value)
      value = value.strip if value.is_a?(String)
      value unless value.respond_to?(:empty?) && value.empty?
    end
  end
end
