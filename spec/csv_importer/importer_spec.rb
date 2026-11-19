# frozen_string_literal: true

require 'tempfile'

RSpec.describe CsvImporter::Importer do
  let(:columns) { { 'email' => :email, 'name' => :name } }

  def import(content, columns: self.columns)
    file = csv_file(content)
    described_class.new(file.path, User, columns: columns).call
  end

  it 'crea un registro por cada fila válida' do
    result = import("email,name\nana@example.com,Ana\nluis@example.com,Luis\n")

    expect(result.created).to eq(2)
    expect(User.count).to eq(2)
  end

  it 'traduce headers personalizados a atributos' do
    import("Correo,Nombre\nana@example.com,Ana\n",
           columns: { 'Correo' => :email, 'Nombre' => :name })

    expect(User.find_by(email: 'ana@example.com').name).to eq('Ana')
  end

  it 'ignora columnas que no están mapeadas' do
    import("email,name,admin\nana@example.com,Ana,true\n")

    expect(User.find_by(email: 'ana@example.com').admin).to be(false)
  end

  it 'registra las filas inválidas con su línea y continúa' do
    result = import("email,name\nana@example.com,Ana\n,Sin email\nluis@example.com,Luis\n")

    expect(result.created).to eq(2)
    expect(result.errors.size).to eq(1)
    expect(result.errors.first[:line]).to eq(3)
  end

  it 'falla antes de tocar la base de datos si faltan headers' do
    expect { import("correo,nombre\nana@example.com,Ana\n") }
      .to raise_error(CsvImporter::InvalidHeaderError, /email/)

    expect(User.count).to eq(0)
  end

  describe 'con atomic: true' do
    def import_atomic(content)
      file = csv_file(content)
      described_class.new(file.path, User, columns: columns, atomic: true).call
    end

    it 'no guarda nada si alguna fila es inválida' do
      result = import_atomic("email,name\nana@example.com,Ana\n,Sin email\nluis@example.com,Luis\n")

      expect(User.count).to eq(0)
      expect(result.rolled_back?).to be(true)
      expect(result.created).to eq(0)
      expect(result.errors.size).to eq(1)
    end

    it 'guarda todo si todas las filas son válidas' do
      result = import_atomic("email,name\nana@example.com,Ana\nluis@example.com,Luis\n")

      expect(User.count).to eq(2)
      expect(result.rolled_back?).to be(false)
      expect(result.created).to eq(2)
    end
  end
end

RSpec.describe CsvImporter::Importer, 'opciones de la v0.2.0' do
  let(:columns) do
    [
      CsvImporter::Column.new(:date, header: 'Fecha', required: true,
                                     transform: ->(value) { Date.strptime(value, '%d/%m/%Y') }),
      CsvImporter::Column.new(:description, header: 'Concepto'),
      CsvImporter::Column.new(:amount_cents, header: 'Importe', type: :decimal,
                                             transform: ->(value) { (value * 100).to_i })
    ]
  end

  def import(content, **options)
    described_class.new(csv_file(content).path, StatementRow, columns: columns, **options).call
  end

  it 'acepta Columns construidas a mano, formato del archivo y defaults' do
    result = import("Fecha;Concepto;Importe\n03/11/2026;CAFE;-2.40\n",
                    csv: { col_sep: ';' }, defaults: { import_id: 1 })

    expect(result.created).to eq(1)
    expect(StatementRow.last).to have_attributes(import_id: 1, date: Date.new(2026, 11, 3), amount_cents: -240)
  end

  it 'no deja que el CSV sobrescriba los defaults aunque esa columna esté declarada' do
    columns << CsvImporter::Column.new(:import_id, type: :integer)

    import("Fecha,Concepto,Importe,import_id\n03/11/2026,CAFE,-2.40,999\n", defaults: { import_id: 1 })

    expect(StatementRow.last.import_id).to eq(1)
  end

  it 'reporta como error de fila un ConversionError lanzado en after_map' do
    hook = lambda do |attributes, _raw_row|
      raise CsvImporter::ConversionError, 'Importe: no puede ser 0' if attributes[:amount_cents].zero?
    end

    result = import("Fecha,Concepto,Importe\n03/11/2026,CAFE,-2.40\n04/11/2026,NADA,0\n",
                    defaults: { import_id: 1 }, after_map: hook)

    expect(result.created).to eq(1)
    expect(result.errors).to eq([{ line: 3, message: 'Importe: no puede ser 0' }])
  end

  it 'deja pasar las demás excepciones de after_map' do
    hook = ->(_attributes, _raw_row) { raise NoMethodError, 'fallo de programación' }

    expect { import("Fecha,Concepto,Importe\n03/11/2026,CAFE,1\n", defaults: { import_id: 1 }, after_map: hook) }
      .to raise_error(NoMethodError)
  end

  it 'en modo atómico, un archivo ilegible a mitad no deja nada guardado' do
    content = "Fecha,Concepto,Importe\n03/11/2026,CAFE,1\n04/11/2026,\"ROTO,2\n"

    expect { import(content, atomic: true, batch_size: 1, defaults: { import_id: 1 }) }
      .to raise_error(CsvImporter::InvalidFileError, /línea 3/)
    expect(StatementRow.count).to eq(0)
  end

  it 'valida los headers contra los nombres dados en headers:' do
    expect { import("03/11/2026,CAFE,1\n", csv: { headers: %w[Fecha Concepto Precio] }) }
      .to raise_error(CsvImporter::InvalidHeaderError, /Importe/)
  end
end
