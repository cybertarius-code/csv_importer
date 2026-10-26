# frozen_string_literal: true

RSpec.describe CsvImporter::Base do
  let(:importer_class) do
    Class.new(described_class) do
      model User
      column :email, header: 'Correo', required: true
      column :name, header: 'Nombre'
      find_by :email
    end
  end

  def run(content, **options)
    file = csv_file(content)
    importer_class.new(file.path, **options).call
  end

  def count_selects(&block)
    count = 0
    counter = ->(*, payload) { count += 1 if payload[:sql].start_with?('SELECT') && payload[:name] != 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
    count
  end

  describe 'lotes' do
    it 'precarga los registros existentes con una consulta por lote' do
      rows = (1..10).map { |i| "u#{i}@example.com,Usuario #{i}" }.join("\n")

      selects = count_selects { run("Correo,Nombre\n#{rows}\n", batch_size: 100) }

      expect(selects).to eq(1)
    end

    it 'actualiza, y no duplica, una clave repetida dentro del mismo lote' do
      result = run("Correo,Nombre\na@example.com,Uno\na@example.com,Dos\n", batch_size: 100)

      expect(result.created).to eq(1)
      expect(result.updated).to eq(1)
      expect(User.count).to eq(1)
      expect(User.first.name).to eq('Dos')
    end

    it 'da el mismo resultado con lotes pequeños' do
      User.create!(email: 'u2@example.com', name: 'Vieja')
      rows = (1..5).map { |i| "u#{i}@example.com,Usuario #{i}" }.join("\n")

      result = run("Correo,Nombre\n#{rows}\n", batch_size: 2)

      expect(result.created).to eq(4)
      expect(result.updated).to eq(1)
    end
  end

  describe 'modo masivo' do
    def count_queries(&block)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == 'SCHEMA' }
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
      count
    end

    it 'crea y actualiza igual que el modo normal' do
      User.create!(email: 'ana@example.com', name: 'Vieja')

      result = run("Correo,Nombre\nana@example.com,Ana\nluis@example.com,Luis\n", bulk: true)

      expect(result.created).to eq(1)
      expect(result.updated).to eq(1)
      expect(User.find_by(email: 'ana@example.com').name).to eq('Ana')
    end

    it 'reporta las filas que no pasan las validaciones del modelo' do
      klass = Class.new(described_class) do
        model User
        column :email
        column :name
        find_by :email
      end
      file = csv_file("email,name\nana@example.com,Ana\n,Sin email\n")

      result = klass.new(file.path, bulk: true).call

      expect(result.created).to eq(1)
      expect(result.errors.first[:line]).to eq(3)
    end

    it 'actualiza, y no duplica, una clave repetida dentro del lote' do
      result = run("Correo,Nombre\na@example.com,Uno\na@example.com,Dos\n", bulk: true)

      expect(result.created).to eq(1)
      expect(result.updated).to eq(1)
      expect(User.count).to eq(1)
      expect(User.first.name).to eq('Dos')
    end

    it 'usa un número de consultas constante por lote' do
      rows = (1..10).map { |i| "u#{i}@example.com,Usuario #{i}" }.join("\n")

      queries = count_queries { run("Correo,Nombre\n#{rows}\n", bulk: true) }

      expect(queries).to be <= 3
    end

    it 'funciona con el modo atómico' do
      result = run("Correo,Nombre\nana@example.com,Ana\n,Sin correo\n", atomic: true, bulk: true)

      expect(User.count).to eq(0)
      expect(result.rolled_back?).to be(true)
    end

    it 'exige un índice único en la clave de find_by' do
      klass = Class.new(described_class) do
        model Tag
        column :label
        find_by :label
      end
      file = csv_file("label\nruby\n")

      expect { klass.new(file.path, bulk: true).call }
        .to raise_error(CsvImporter::ConfigurationError, /índice único/)
    end
  end

  it 'importa usando la configuración declarada' do
    result = run("Correo,Nombre\nana@example.com,Ana\n")

    expect(result.created).to eq(1)
    expect(User.find_by(email: 'ana@example.com').name).to eq('Ana')
  end

  it 'actualiza los registros existentes gracias a find_by' do
    User.create!(email: 'ana@example.com', name: 'Vieja')

    result = run("Correo,Nombre\nana@example.com,Ana\nluis@example.com,Luis\n")

    expect(result.created).to eq(1)
    expect(result.updated).to eq(1)
    expect(User.find_by(email: 'ana@example.com').name).to eq('Ana')
  end

  it 'reporta como error de fila un campo obligatorio vacío' do
    result = run("Correo,Nombre\n,Sin correo\n")

    expect(result.created).to eq(0)
    expect(result.errors.first[:message]).to include('Correo')
  end

  it 'respeta el modo atómico' do
    result = run("Correo,Nombre\nana@example.com,Ana\n,Sin correo\n", atomic: true)

    expect(User.count).to eq(0)
    expect(result.rolled_back?).to be(true)
  end

  it 'las subclases heredan la configuración sin alterar a la clase padre' do
    child = Class.new(importer_class) { column :age, type: :integer }

    expect(child.definition.columns.map(&:attribute)).to eq(%i[email name age])
    expect(importer_class.definition.columns.map(&:attribute)).to eq(%i[email name])
  end

  describe 'configuración inválida' do
    it 'exige declarar el modelo' do
      expect { Class.new(described_class).new('x.csv') }
        .to raise_error(CsvImporter::ConfigurationError, /model/)
    end

    it 'exige que find_by use columnas declaradas' do
      klass = Class.new(described_class) do
        model User
        column :email
        find_by :name
      end

      expect { klass.new('x.csv') }
        .to raise_error(CsvImporter::ConfigurationError, /name/)
    end
  end

  describe 'tipos y transformaciones' do
    let(:importer_class) do
      Class.new(described_class) do
        model User
        column :email
        column :birth_date, header: 'nacimiento', type: :date
        column :age, type: :integer
        column :name, transform: lambda(&:upcase)
      end
    end

    it 'convierte tipos y aplica transformaciones' do
      run("email,nacimiento,age,name\nana@example.com,1990-05-20,34,ana\n")
      user = User.find_by(email: 'ana@example.com')

      expect(user.birth_date).to eq(Date.new(1990, 5, 20))
      expect(user.age).to eq(34)
      expect(user.name).to eq('ANA')
    end

    it 'reporta valores inválidos por fila y sigue con el resto' do
      result = run("email,nacimiento,age,name\nana@example.com,1990-05-20,abc,ana\nluis@example.com,1985-01-01,30,luis\n")

      expect(result.created).to eq(1)
      expect(result.errors.first[:line]).to eq(2)
      expect(result.errors.first[:message]).to include('age')
    end

    it 'falla al declarar un tipo desconocido' do
      expect { Class.new(described_class) { column :age, type: :entero } }
        .to raise_error(ArgumentError, /entero/)
    end
  end
end
