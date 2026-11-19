# frozen_string_literal: true

require 'tempfile'

module CsvHelpers
  def csv_file(content)
    Tempfile.new(['data', '.csv']).tap do |file|
      file.binmode
      file.write(content)
      file.close
    end
  end

  def fixture_path(name)
    File.expand_path("../fixtures/#{name}", __dir__)
  end
end
