# frozen_string_literal: true

require "csv"

module CsvImporter
  # This class is responsible for importing CSV data into a specified ActiveRecord model.
  class Importer
    def initialize(file_path, model)
      @file_path = file_path
      @model = model
    end

    def call
      count = 0

      CSV.foreach(@file_path, headers: true) do |row|
        @model.create!(row.to_h)
        count += 1
      end

      count
    end
  end
end
