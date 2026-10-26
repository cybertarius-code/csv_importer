# frozen_string_literal: true

require 'tempfile'

module CsvHelpers
  def csv_file(content)
    Tempfile.new(['data', '.csv']).tap do |file|
      file.write(content)
      file.close
    end
  end
end
