# frozen_string_literal: true

RSpec.describe CsvImporter::RowMapper do
  subject(:mapper) { described_class.new({ 'Correo' => :email, 'Nombre' => :name }) }

  it 'traduce headers a atributos y descarta el resto' do
    attributes = mapper.call('Correo' => 'ana@example.com', 'Nombre' => 'Ana', 'admin' => 'true')

    expect(attributes).to eq(email: 'ana@example.com', name: 'Ana')
  end

  describe 'defaults:' do
    it 'añade valores fijos que el CSV no puede sobrescribir' do
      mapper = described_class.new({ 'Correo' => :email, 'Equipo' => :team_id }, defaults: { 'team_id' => 7 })

      expect(mapper.call('Correo' => 'ana@example.com', 'Equipo' => '99')).to eq(email: 'ana@example.com', team_id: 7)
    end
  end

  describe 'after_map:' do
    let(:row) { { 'Correo' => 'ana@example.com', 'Nombre' => 'Ana', 'Extra' => 'x' } }

    it 'recibe los atributos (con los defaults) y la fila cruda' do
      seen = nil
      hook = ->(attributes, raw_row) { seen = [attributes.dup, raw_row] }

      described_class.new({ 'Correo' => :email }, defaults: { team_id: 7 }, after_map: hook).call(row)

      expect(seen).to eq([{ email: 'ana@example.com', team_id: 7 }, row])
    end

    it 'acepta cambios en sitio' do
      hook = ->(attributes, _raw_row) { attributes[:name] = attributes[:name].upcase }

      expect(described_class.new({ 'Nombre' => :name }, after_map: hook).call(row)).to eq(name: 'ANA')
    end

    it 'usa el Hash que devuelva el gancho' do
      hook = ->(attributes, raw_row) { attributes.merge(note: raw_row['Extra']) }

      expect(described_class.new({ 'Nombre' => :name }, after_map: hook).call(row)).to eq(name: 'Ana', note: 'x')
    end

    it 'encadena varios ganchos en orden' do
      hooks = [->(a, _) { a.merge(step: 1) }, ->(a, _) { a.merge(step: a[:step] + 1) }]

      expect(described_class.new({ 'Nombre' => :name }, after_map: hooks).call(row)).to eq(name: 'Ana', step: 2)
    end

    it 'rechaza un gancho que no responde a call' do
      expect { described_class.new({ 'Nombre' => :name }, after_map: 'no') }
        .to raise_error(CsvImporter::ConfigurationError, /after_map/)
    end
  end
end
