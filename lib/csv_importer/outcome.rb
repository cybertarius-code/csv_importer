# frozen_string_literal: true

module CsvImporter
  # Qué pasó con una fila. :status es :created, :updated o :invalid.
  Outcome = Struct.new(:line, :status, :message, keyword_init: true)
end
