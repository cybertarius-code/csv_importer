# frozen_string_literal: true

# Uso: bundle exec ruby benchmark/import_benchmark.rb [filas]

require 'csv'
require 'tempfile'
require 'csv_importer'

ROWS = (ARGV[0] || 50_000).to_i

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false

ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :email, index: { unique: true }, null: false
    t.string :name
    t.date :birth_date
    t.integer :age
  end
end

# Modelo de ejemplo para la importación
class User < ActiveRecord::Base
  validates :email, presence: true
end

# Importadores de ejemplo para la importación de CSV
class PlainImporter < CsvImporter::Base
  model User
  column :email, required: true
  column :name
  column :birth_date, type: :date
  column :age, type: :integer
end

# Hereda las columnas de PlainImporter y añade find_by
class UpsertImporter < PlainImporter
  find_by :email
end

def build_csv(total)
  file = Tempfile.new(['bench', '.csv'])

  CSV.open(file.path, 'w') do |csv|
    csv << %w[email name birth_date age]
    total.times do |i|
      csv << ["user#{i}@example.com", "Usuario #{i}", format('1990-01-%02d', i % 28 + 1), 18 + (i % 60)]
    end
  end

  file
end

def rss_mb
  `ps -o rss= -p #{Process.pid}`.to_i / 1024
end

def measure(label)
  queries = 0
  counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' }
  result = nil

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { result = yield }
  seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

  puts format('%-30s %7.2fs %9d consultas  creados: %-6d actualizados: %-6d RSS: %d MB',
              label, seconds, queries, result.created, result.updated, rss_mb)
end

csv = build_csv(ROWS)
puts "Filas: #{ROWS}\n\n"

measure('Crear (sin find_by)') { PlainImporter.new(csv.path).call }

User.delete_all
measure('Masivo: crear')         { UpsertImporter.new(csv.path, bulk: true).call }
measure('Masivo: reimportar')    { UpsertImporter.new(csv.path, bulk: true).call }

User.delete_all
measure('Masivo atómico: crear') { UpsertImporter.new(csv.path, atomic: true, bulk: true).call }

def time_it(label)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  puts format('%-34s %7.2fs', label, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
end

puts "\nDesglose por etapa (#{ROWS} filas)"

parser = CsvImporter::Parser.new(csv.path)
mapper = CsvImporter::RowMapper.new(UpsertImporter.definition.columns)

time_it('1. Solo leer el CSV')          { parser.each_row { |_line, _raw| } }
time_it('2. + convertir tipos')         { parser.each_row { |_line, raw| mapper.call(raw) } }
time_it('3. + instanciar y validar')    { parser.each_row { |_line, raw| User.new(mapper.call(raw)).valid? } }
