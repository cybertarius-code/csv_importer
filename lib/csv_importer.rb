# frozen_string_literal: true

require 'active_record'
require_relative 'csv_importer/version'
require_relative 'csv_importer/errors'
require_relative 'csv_importer/types'
require_relative 'csv_importer/column'
require_relative 'csv_importer/definition'
require_relative 'csv_importer/parser'
require_relative 'csv_importer/row_mapper'
require_relative 'csv_importer/result'
require_relative 'csv_importer/importer'
require_relative 'csv_importer/base'
require_relative 'csv_importer/outcome'
require_relative 'csv_importer/transactional'
require_relative 'csv_importer/record_persister'
require_relative 'csv_importer/bulk_persister'

# CsvImporter is a Ruby gem that provides a declarative DSL for importing CSV files into ActiveRecord models. It allows
# you to define columns, types, and search keys in a class and import a CSV file into the database with row-level error
# handling, atomic mode, and optional bulk mode.
module CsvImporter
end
