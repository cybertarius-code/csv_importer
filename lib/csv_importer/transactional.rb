# frozen_string_literal: true

module CsvImporter
  # Mixin: da a un persister el método `atomically`. Requiere @model.
  module Transactional
    # Ejecuta el bloque en una transacción; si devuelve un valor falso, revierte.
    def atomically
      committed = false

      @model.transaction(requires_new: true) do
        committed = yield
        raise ActiveRecord::Rollback unless committed
      end

      committed
    end
  end
end
