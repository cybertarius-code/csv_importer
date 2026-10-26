# frozen_string_literal: true

RSpec.describe CsvImporter::RowMapper do
  subject(:mapper) { described_class.new('Correo' => :email, 'Nombre' => :name) }

  it 'traduce headers a atributos y descarta el resto' do
    attributes = mapper.call('Correo' => 'ana@example.com', 'Nombre' => 'Ana', 'admin' => 'true')

    expect(attributes).to eq(email: 'ana@example.com', name: 'Ana')
  end
end
