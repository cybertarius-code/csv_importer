# frozen_string_literal: true

require 'csv_importer'

# Carga los helpers de spec/support (debe ir antes de RSpec.configure)
Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |file| require file }

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false

ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :email, index: { unique: true }
    t.string :name
    t.boolean :admin, default: false
    t.date :birth_date
    t.integer :age
  end

  create_table :tags do |t|
    t.string :label
  end
end

class User < ActiveRecord::Base
  validates :email, presence: true
end

class Tag < ActiveRecord::Base; end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.include CsvHelpers

  # Cada test corre dentro de una transacción que se revierte
  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
