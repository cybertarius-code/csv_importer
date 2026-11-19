# frozen_string_literal: true

require_relative 'lib/csv_importer/version'

Gem::Specification.new do |spec|
  spec.name = 'csv_importer'
  spec.version = CsvImporter::VERSION
  spec.authors = ['Arius Cybert']
  spec.email = ['cybertarius@gmail.com']

  spec.summary = 'Importa archivos CSV a ActiveRecord con un DSL declarativo.'
  spec.description = 'Declara columnas, tipos y claves de búsqueda en una clase y ' \
                     'importa un CSV a la base de datos, con errores por fila, ' \
                     'modo atómico y modo masivo opcional.'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.files = Dir['lib/**/*.rb', 'README.md', 'LICENSE.txt', 'CHANGELOG.md']

  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.add_dependency 'activerecord', '>= 7.0'
  spec.add_dependency 'csv'
end
