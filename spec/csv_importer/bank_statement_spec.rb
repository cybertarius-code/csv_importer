# frozen_string_literal: true

require 'digest'

# De punta a punta, con el DSL: así usará Tholos la gema (ADR-0017).
RSpec.describe 'Importar un extracto bancario' do
  let(:sabadell) do
    Class.new(CsvImporter::Base) do
      model StatementRow
      csv col_sep: '|', encoding: 'Windows-1252',
          headers: %w[fecha concepto fecha_valor importe saldo ref1 ref2]

      to_cents = ->(value) { (value * 100).to_i }
      column :date,          header: 'fecha', required: true,
                             transform: ->(value) { Date.strptime(value, '%d/%m/%Y') }
      column :description,   header: 'concepto', required: true
      column :amount_cents,  header: 'importe', type: :decimal, required: true, transform: to_cents
      column :balance_cents, header: 'saldo', type: :decimal, transform: to_cents
    end
  end

  # Huella con los valores originales del fichero, como en ADR-0017 §C
  let(:fingerprint) do
    lambda do |attributes, raw_row|
      key = ['cuenta-1', *raw_row.values_at('fecha', 'importe', 'concepto', 'saldo')].join('|')
      attributes[:import_ref] = Digest::SHA256.hexdigest(key)
    end
  end

  it 'carga el fichero sin títulos, en Windows-1252 y separado por |' do
    result = sabadell.new(fixture_path('sabadell.txt'), atomic: true,
                                                        defaults: { import_id: 42 }, after_map: fingerprint).call

    expect(result).to have_attributes(success?: true, created: 5)
    expect(StatementRow.where(import_id: 42).count).to eq(5)
    expect(StatementRow.order(:id).first).to have_attributes(
      date: Date.new(2026, 11, 7), description: 'ABONO TRANSFERENCIA PEÑA FICTICIA SL',
      amount_cents: 123_456, balance_cents: 242_861
    )
  end

  it 'distingue por el saldo dos movimientos iguales del mismo día' do
    sabadell.new(fixture_path('sabadell.txt'), defaults: { import_id: 1 }, after_map: fingerprint).call

    cafes = StatementRow.where(description: 'CAFETERIA LUNA')
    expect(cafes.map(&:import_ref).uniq.size).to eq(2)
  end

  it 'en modo atómico no guarda nada y reporta cada fila con su línea' do
    broken = csv_file("03/11/2026|CAFE|03/11/2026|-2.40|10.00||\n31/02/2026|MAL|01/03/2026|-1.00|9.00||\n" \
                      "04/11/2026||04/11/2026|abc|9.00||\n".encode('Windows-1252'))

    result = sabadell.new(broken.path, atomic: true, defaults: { import_id: 1 }).call

    expect(result.rolled_back?).to be(true)
    expect(StatementRow.count).to eq(0)
    expect(result.errors.map { |error| error[:line] }).to eq([2, 3])
  end

  it 'combina un gancho de la clase con el de la llamada, en ese orden' do
    calls = []
    klass = Class.new(sabadell) { after_map { |_attributes, _raw_row| calls << :clase } }

    klass.new(fixture_path('sabadell.txt'), defaults: { import_id: 1 },
                                            after_map: ->(*) { calls << :llamada }).call

    expect(calls.first(2)).to eq(%i[clase llamada])
  end

  it 'lee un fichero con ; y líneas previas' do
    klass = Class.new(CsvImporter::Base) do
      model StatementRow
      csv col_sep: ';', encoding: 'Windows-1252', skip_lines: 2

      euros = ->(value) { (BigDecimal(value.delete('.').tr(',', '.')) * 100).to_i }
      column :date,         header: 'Fecha', transform: ->(value) { Date.strptime(value, '%d/%m/%Y') }
      column :description,  header: 'Concepto'
      column :amount_cents, header: 'Importe', transform: euros
      column :balance_cents, header: 'Saldo', transform: euros
    end

    result = klass.new(fixture_path('semicolon_with_preamble.csv'), defaults: { import_id: 1 }).call

    expect(result.created).to eq(3)
    expect(StatementRow.order(:id).last).to have_attributes(description: 'NÓMINA EMPRESA FICTICIA',
                                                            amount_cents: 123_456, balance_cents: 243_216)
  end
end
