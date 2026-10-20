# frozen_string_literal: true

require "tempfile"

RSpec.describe CsvImporter::Importer do
  def csv_file(content)
    file = Tempfile.new(["users", ".csv"])
    file.write(content)
    file.close
    file
  end

  let(:file) do
    csv_file("email,name\nana@example.com,Ana\nluis@example.com,Luis\n")
  end

  it "crea un registro por cada fila" do
    expect { described_class.new(file.path, User).call }
      .to change(User, :count).by(2)
  end

  it "asigna los atributos según los headers" do
    described_class.new(file.path, User).call

    expect(User.find_by(email: "ana@example.com").name).to eq("Ana")
  end

  it "devuelve cuántas filas importó" do
    expect(described_class.new(file.path, User).call).to eq(2)
  end
end
