# frozen_string_literal: true

module CsvImporter
  class Result
    attr_reader :created, :updated

    def initialize
      @created = 0
      @updated = 0
      @errors = []
      @rolled_back = false
    end

    def add_created
      @created += 1
    end

    def add_updated
      @updated += 1
    end

    def add_error(line:, message:)
      @errors << { line: line, message: message }
    end

    def errors
      @errors.sort_by { |error| error[:line] }
    end

    # Nada se guardó: los contadores deben reflejarlo
    def rollback!
      @created = 0
      @updated = 0
      @rolled_back = true
    end

    def rolled_back?
      @rolled_back
    end

    def success?
      @errors.empty?
    end
  end
end
