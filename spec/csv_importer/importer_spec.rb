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
