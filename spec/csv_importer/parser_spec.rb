# frozen_string_literal: true

RSpec.describe CsvImporter::Parser do
  def rows(parser)
    parser.each_row.to_a
  end

  describe 'por defecto' do
    it 'lee la fila de títulos y numera los registros desde la línea 2' do
      parser = described_class.new(csv_file("a,b\n1,2\n3,4\n").path)

      expect(parser.headers).to eq(%w[a b])
      expect(rows(parser)).to eq([[2, { 'a' => '1', 'b' => '2' }], [3, { 'a' => '3', 'b' => '4' }]])
    end

    it 'tolera el BOM de Excel' do
      parser = described_class.new(csv_file("﻿a,b\n1,2\n").path)

      expect(parser.headers).to eq(%w[a b])
    end
  end

  describe 'col_sep:' do
    it 'usa el separador indicado' do
      parser = described_class.new(csv_file("a;b\n1,5;2\n").path, col_sep: ';')

      expect(rows(parser)).to eq([[2, { 'a' => '1,5', 'b' => '2' }]])
    end
  end

  describe 'encoding:' do
    let(:latin) { csv_file("concepto\nCOMISIÓN\n".encode('Windows-1252')) }

    it 'convierte a UTF-8 una codificación sin destino explícito' do
      parser = described_class.new(latin.path, encoding: 'Windows-1252')
      value = rows(parser).first.last['concepto']

      expect(parser.encoding).to eq('Windows-1252:UTF-8')
      expect(value).to eq('COMISIÓN')
      expect(value.encoding).to eq(Encoding::UTF_8)
    end

    it 'respeta una conversión explícita' do
      parser = described_class.new(latin.path, encoding: 'ISO-8859-1:UTF-8')

      expect(rows(parser).first.last['concepto']).to eq('COMISIÓN')
    end

    it 'rechaza una codificación desconocida al construirse' do
      expect { described_class.new('x.csv', encoding: 'Klingon') }
        .to raise_error(CsvImporter::ConfigurationError, /Klingon/)
    end
  end

  describe 'headers:' do
    it 'usa los nombres dados y numera desde la línea 1' do
      parser = described_class.new(csv_file("1|2\n3|4\n").path, col_sep: '|', headers: %i[a b])

      expect(parser.headers).to eq(%w[a b])
      expect(rows(parser)).to eq([[1, { 'a' => '1', 'b' => '2' }], [2, { 'a' => '3', 'b' => '4' }]])
    end

    it 'exige una lista no vacía de nombres' do
      expect { described_class.new('x.csv', headers: []) }.to raise_error(CsvImporter::ConfigurationError)
      expect { described_class.new('x.csv', headers: true) }.to raise_error(CsvImporter::ConfigurationError)
      expect { described_class.new('x.csv', headers: ['a', '']) }.to raise_error(CsvImporter::ConfigurationError)
    end
  end

  describe 'skip_lines:' do
    it 'salta las líneas previas y numera con la línea real del archivo' do
      parser = described_class.new(csv_file("Extracto\nPeriodo\na,b\n1,2\n").path, skip_lines: 2)

      expect(parser.headers).to eq(%w[a b])
      expect(rows(parser)).to eq([[4, { 'a' => '1', 'b' => '2' }]])
    end

    it 'se combina con headers:' do
      parser = described_class.new(csv_file("Extracto\n1,2\n").path, skip_lines: 1, headers: %w[a b])

      expect(rows(parser)).to eq([[2, { 'a' => '1', 'b' => '2' }]])
    end

    it 'exige un entero no negativo' do
      expect { described_class.new('x.csv', skip_lines: -1) }.to raise_error(CsvImporter::ConfigurationError)
      expect { described_class.new('x.csv', skip_lines: '1') }.to raise_error(CsvImporter::ConfigurationError)
    end
  end

  describe 'archivos ilegibles' do
    it 'traduce un CSV mal formado a InvalidFileError con la línea real' do
      parser = described_class.new(csv_file("Extracto\na,b\n1,2\n3,\"4\n").path, skip_lines: 1)

      expect { rows(parser) }.to raise_error(CsvImporter::InvalidFileError, /línea 4: Unclosed quoted field\z/)
    end

    it 'avisa si el archivo no está en UTF-8 y sugiere encoding:' do
      parser = described_class.new(csv_file("a\nCOMISI\xD3N\n".b).path)

      expect { rows(parser) }.to raise_error(CsvImporter::InvalidFileError, /no está en UTF-8 \(línea 2\).*encoding:/)
    end

    it 'avisa si hay bytes que no existen en la codificación indicada' do
      parser = described_class.new(csv_file("a\nx\x81y\n".b).path, encoding: 'Windows-1252')

      expect { rows(parser) }.to raise_error(CsvImporter::InvalidFileError, /WINDOWS-1252/)
    end

    it 'deja pasar los errores de quien consume las filas' do
      parser = described_class.new(csv_file("a\n1\n").path)

      consumer = ->(*) { raise Encoding::CompatibilityError, 'de la base de datos' }

      expect { parser.each_row(&consumer) }.to raise_error(Encoding::CompatibilityError)
    end
  end

  describe '.validate_options!' do
    it 'rechaza opciones desconocidas' do
      expect { described_class.validate_options!(quote_char: "'") }
        .to raise_error(CsvImporter::ConfigurationError, /quote_char/)
    end
  end

  describe 'fichero sintético con el formato de Sabadell' do
    subject(:parser) do
      described_class.new(fixture_path('sabadell.txt'),
                          col_sep: '|', encoding: 'Windows-1252',
                          headers: %w[fecha concepto fecha_valor importe saldo ref1 ref2])
    end

    it 'lee todas las filas, en UTF-8 y numeradas desde 1' do
      lines = rows(parser)

      expect(lines.map(&:first)).to eq([1, 2, 3, 4, 5])
      expect(lines[0].last['concepto']).to eq('ABONO TRANSFERENCIA PEÑA FICTICIA SL')
      expect(lines[1].last).to include('concepto' => 'COMISIÓN DIVISA', 'importe' => '-1.15', 'ref1' => nil)
    end
  end

  describe 'fichero sintético con ; y líneas previas' do
    subject(:parser) do
      described_class.new(fixture_path('semicolon_with_preamble.csv'),
                          col_sep: ';', encoding: 'Windows-1252', skip_lines: 2)
    end

    it 'encuentra los títulos tras las líneas previas' do
      expect(parser.headers).to eq(%w[Fecha Concepto Importe Saldo])
      expect(rows(parser).map(&:first)).to eq([4, 5, 6])
      expect(rows(parser).first.last['Concepto']).to eq('CAFETERÍA LUNA')
    end
  end
end
