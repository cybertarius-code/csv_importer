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

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .rubocop.yml])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.add_dependency 'activerecord', '>= 7.0'
  spec.add_dependency 'csv'
end
