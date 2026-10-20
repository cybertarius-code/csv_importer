# frozen_string_literal: true

require "csv_importer"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false

ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :email
    t.string :name
  end
end

class User < ActiveRecord::Base; end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  # Cada test corre dentro de una transacción que se revierte
  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
