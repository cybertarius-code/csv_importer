# csv_importer

Importa archivos CSV a la base de datos de una aplicación Rails (o cualquier
proyecto con ActiveRecord) declarando qué columnas se leen, cómo se convierten
y cómo se reconocen los registros que ya existen.

```ruby
class UserImporter < CsvImporter::Base
  model User

  column :email,      header: "Correo", required: true
  column :name,       header: "Nombre"
  column :birth_date, header: "Nacimiento", type: :date

  find_by :email # si el email ya existe, actualiza; si no, crea
end

result = UserImporter.new("usuarios.csv").call
result.created # => 120
result.updated # => 30
result.errors  # => [{ line: 5, message: "Correo: no puede estar vacío" }]
```

## Características

- DSL declarativo: `model`, `column`, `find_by`, `csv` y `after_map`.
- Formatos habituales de los bancos: separador propio (`;`, `|`), cualquier
  codificación (Windows-1252...), archivos sin fila de títulos y líneas previas.
- Valores fijos por fila (`defaults:`) que el CSV no puede sobrescribir.
- Gancho por fila (`after_map`) para campos calculados a partir de varias columnas.
- Conversión de tipos y transformaciones por columna.
- Las filas inválidas no detienen la importación: se acumulan con su número de fila.
- Modo atómico: todo o nada, con transacción.
- Procesamiento por lotes, con memoria acotada aunque el archivo sea enorme.
- Modo masivo opcional (`insert_all` / `upsert_all`) para archivos grandes.
- Seguro por defecto: solo se escriben las columnas declaradas.

## Instalación

La gema no está en RubyGems. Se instala desde GitHub, fijando una etiqueta, en el
`Gemfile` de la aplicación:

```ruby
gem "csv_importer", github: "cybertarius-code/csv_importer", tag: "v0.2.0"
```

Luego `bundle install`. Usa siempre `tag:`: sin etiqueta, cada `bundle update`
traería lo último de `main`. Evita `path:` salvo para desarrollar la gema en
local, porque esa ruta no existe en la CI ni en el servidor.

Probada con Ruby 3.4 y ActiveRecord 7 o superior. Con Ruby 3.4 o posterior,
`csv` ya no forma parte de la biblioteca estándar; la gema la declara como
dependencia, así que no necesitas añadirla tú.

## Uso

### Declarar un importador

En una aplicación Rails, un buen sitio es `app/importers/` (Rails carga
automáticamente cualquier carpeta dentro de `app/`):

```ruby
# app/importers/user_importer.rb
class UserImporter < CsvImporter::Base
  model User

  column :email, header: "Correo", required: true
  column :name,  header: "Nombre"
  column :age,   type: :integer

  find_by :email
end
```

### Ejecutarlo

```ruby
result = UserImporter.new(params[:file].path).call

if result.success?
  redirect_to users_path, notice: "#{result.created} creados, #{result.updated} actualizados"
else
  # result.errors: [{ line: 3, message: "..." }, ...]
end
```

## El DSL

### `model`

La clase de ActiveRecord donde se guardan las filas. Obligatorio.

### `column(atributo, **opciones)`

| Opción | Descripción |
|---|---|
| `header:` | Nombre de la columna en el CSV. Por defecto, el nombre del atributo. |
| `type:` | Conversión de tipo: `:string`, `:integer`, `:decimal`, `:date`, `:boolean`. |
| `required:` | Si es `true`, una celda vacía es un error de esa fila. |
| `transform:` | Un lambda que recibe el valor (ya convertido si hay `type:`) y devuelve el definitivo. |

Reglas a tener en cuenta:

- Los espacios al principio y al final se eliminan, y una celda vacía se trata como `nil`
  (sin pasar por `type:` ni `transform:`).
- `type:` se aplica antes que `transform:`.
- Las columnas del CSV que no declares se ignoran. Esto evita que un archivo
  escriba atributos no autorizados (por ejemplo, un `admin`).
- Todos los headers declarados deben existir en el CSV, aunque la columna no sea
  `required:`. Si falta alguno, se lanza `CsvImporter::InvalidHeaderError` antes de
  tocar la base de datos.

```ruby
column :name,       transform: ->(value) { value.upcase }
column :birth_date, header: "Nacimiento",
                    transform: ->(value) { Date.strptime(value, "%d/%m/%Y") }
```

### `find_by(*atributos)`

Los atributos que identifican un registro existente. Si hay una fila con esa
clave en la base de datos, se actualiza; si no, se crea. Cada atributo debe estar
declarado como `column`. Sin `find_by`, todas las filas se crean.

### `csv(**opciones)`

El formato del archivo. Todas las opciones son opcionales:

| Opción | Por defecto | Descripción |
|---|---|---|
| `col_sep:` | `","` | Separador de columnas: `";"`, `"\|"`, `"\t"`... |
| `encoding:` | `"bom\|utf-8"` | Codificación del archivo. Si no es UTF-8, el texto se convierte a UTF-8 al leerlo: `"Windows-1252"` equivale a `"Windows-1252:UTF-8"`. |
| `headers:` | — | Para archivos **sin fila de títulos**: los nombres de las columnas, en orden. Los `header:` de las columnas se refieren a estos nombres. |
| `skip_lines:` | `0` | Líneas que se saltan al principio (el banco suele poner el titular, la cuenta o el periodo antes de los títulos). |

Una opción desconocida o inválida (una codificación que no existe, `skip_lines: -1`)
lanza `CsvImporter::ConfigurationError` al declarar la clase.

```ruby
# Extracto con ";" en Windows-1252 y dos líneas antes de los títulos
class BbvaStatement < CsvImporter::Base
  model ImportRow
  csv col_sep: ";", encoding: "Windows-1252", skip_lines: 2

  column :date,        header: "Fecha", transform: ->(v) { Date.strptime(v, "%d/%m/%Y") }
  column :description, header: "Concepto"
end

# Extracto sin títulos, separado por "|"
class SabadellStatement < CsvImporter::Base
  model ImportRow
  csv col_sep: "|", encoding: "Windows-1252",
      headers: %w[fecha concepto fecha_valor importe saldo ref1 ref2]

  column :date,         header: "fecha", required: true,
                        transform: ->(v) { Date.strptime(v, "%d/%m/%Y") }
  column :description,  header: "concepto", required: true
  column :amount_cents, header: "importe", type: :decimal, transform: ->(v) { (v * 100).to_i }
end
```

### `after_map`

Un gancho que se ejecuta en cada fila después de convertirla. Recibe los
atributos (ya convertidos y con los `defaults:`) y la fila original del CSV
(`{ "header" => "texto" }`). Sirve para campos que dependen de varias columnas:

```ruby
class CargoAbonoStatement < CsvImporter::Base
  model ImportRow
  column :charge, header: "Cargo", type: :decimal
  column :credit, header: "Abono", type: :decimal

  after_map do |attributes, _raw_row|
    attributes[:amount] = (attributes.delete(:credit) || 0) - (attributes.delete(:charge) || 0)
  end
end
```

- Puede modificar `attributes` en sitio o devolver un `Hash` nuevo: si devuelve
  un `Hash`, se guarda ese; si devuelve otra cosa, se guarda `attributes`.
- Si lanza `CsvImporter::ConversionError`, la fila se reporta como error (con su
  línea) y la importación sigue, igual que una celda mal formada. Cualquier otra
  excepción se propaga: se considera un fallo de programación.
- Acepta un bloque o cualquier objeto con `call(attributes, raw_row)`. Se pueden
  declarar varios; se ejecutan en orden.

### Herencia

Una subclase hereda la configuración y puede ampliarla o redefinir columnas sin
afectar a la clase padre:

```ruby
class AdminUserImporter < UserImporter
  column :role # se añade solo a este importador
end
```

Las opciones de `csv` se mezclan con las del padre (la subclase puede cambiar
solo `skip_lines:`, por ejemplo) y los `after_map` del padre se ejecutan antes que
los de la subclase.

## Tipos

| Tipo | Acepta |
|---|---|
| `:string` | Cualquier texto |
| `:integer` | Enteros (`"42"`) |
| `:decimal` | Decimales con punto (`"12.50"`), devueltos como `BigDecimal` |
| `:date` | Fechas ISO 8601 (`"2024-05-20"`) |
| `:boolean` | `true`, `1`, `yes`, `si`, `sí` / `false`, `0`, `no` (sin distinguir mayúsculas) |

Para otros formatos de fecha, no declares `type:` y usa `transform:` con
`Date.strptime`, como en el ejemplo de arriba.

### Tipos propios

```ruby
# config/initializers/csv_importer.rb
CsvImporter::Types.register(:money) do |value|
  BigDecimal(value.delete(".").tr(",", "."))
end
```

El bloque recibe un `String` y debe devolver el valor convertido. Si el valor no
es válido, debe lanzar `ArgumentError`: la fila se reporta como error y la
importación continúa. Un tipo desconocido falla al declarar la clase, no durante
la importación.

## Resultado

`call` devuelve un `CsvImporter::Result`:

| Método | Significado |
|---|---|
| `created` | Registros creados |
| `updated` | Registros que ya existían y se actualizaron |
| `errors` | Lista de `{ line:, message: }`, ordenada por fila |
| `success?` | `true` si no hubo ningún error |
| `rolled_back?` | `true` si se revirtió una importación atómica |

`line` es la línea del archivo: cuenta las líneas saltadas con `skip_lines:` y la
de títulos. Sin `skip_lines:`, el primer registro es la línea 2 o, con `headers:`
(sin fila de títulos), la línea 1.

## Opciones

```ruby
UserImporter.new(path, atomic: true, bulk: true, batch_size: 500,
                 defaults: { team_id: 3 }, after_map: ->(attributes, raw_row) { ... }).call
```

El formato del archivo y las columnas son de la clase; estas opciones son de cada
ejecución.

### `defaults:`

Valores fijos que se añaden a cada fila, como la cuenta o la importación a la
que pertenecen, que no vienen en el archivo:

```ruby
BankStatement.new(path, defaults: { import_id: import.id }).call
```

El CSV **no puede sobrescribirlos**: si una columna declarada tiene el mismo
nombre, gana el valor de `defaults:`. Los ganchos `after_map` ya los ven.

### `after_map:`

Un gancho como el del DSL, para lo que depende de la ejecución (por ejemplo, una
huella que incluye la cuenta). Se ejecuta después de los `after_map` de la clase.

```ruby
BankStatement.new(path, after_map: ->(attributes, raw_row) {
  attributes[:import_ref] = Digest::SHA256.hexdigest([account.id, *raw_row.values].join("|"))
}).call
```

### `atomic: true`

Todo o nada. Se procesa el archivo completo acumulando los errores y, si hay
alguno, se revierte todo: `created` y `updated` quedan en 0 y `rolled_back?`
devuelve `true`. Así se ven todos los problemas del archivo de una vez.

Es seguro llamarlo dentro de una transacción propia de tu aplicación: usa un
*savepoint*, así que el rollback afecta solo a la importación.

### `batch_size:`

Filas por lote (por defecto, 1.000). Acota el uso de memoria y el tamaño de las
consultas. En cada lote, los registros existentes se buscan con una sola consulta.

### `bulk: true`

Usa `insert_all` / `upsert_all` en lugar de guardar fila a fila. Es varias veces
más rápido, pero **cede cosas**:

- **Los callbacks no se ejecutan** (`after_create`, contadores de caché,
  indexación, auditoría...).
- **Las validaciones se ejecutan sobre un registro nuevo con los atributos de la
  fila**, no sobre el registro existente. Una validación que dependa de columnas
  ausentes en el CSV puede fallar al actualizar.
- **Las validaciones que consultan la base de datos** (`uniqueness`) hacen una
  consulta por fila y anulan buena parte de la ganancia.
- **Con `find_by` hace falta un índice único** sobre esas columnas. Si no existe,
  `call` lanza `CsvImporter::ConfigurationError` antes de leer el archivo.
- **Colación de la base de datos:** si tu base de datos considera iguales
  `Ana@x.com` y `ana@x.com`, la base de datos actualizará una fila mientras el
  conteo de `created` / `updated` (que compara en Ruby) puede discrepar. Normaliza
  la clave con `transform:` (por ejemplo, `->(v) { v.downcase }`).

Sin `find_by`, el modo masivo hace un `insert_all` y no detecta duplicados.

## API pública sin DSL: `Importer` y `Column`

`Base` es azúcar sobre `CsvImporter::Importer`, que se puede usar directamente
cuando las columnas no se conocen al escribir el código (por ejemplo, un mapeo
guardado en la base de datos por cada cuenta):

```ruby
columns = profile.columns.map do |c|
  CsvImporter::Column.new(c.attribute, header: c.header, type: c.type, required: c.required)
end

result = CsvImporter::Importer.new(
  path, ImportRow,
  columns: columns,
  csv: { col_sep: profile.col_sep, encoding: profile.encoding, skip_lines: profile.skip_lines },
  defaults: { import_id: import.id },
  after_map: ->(attributes, raw_row) { ... },
  atomic: true
).call
```

`CsvImporter::Column.new(atributo, header:, type:, required:, transform:)` acepta
las mismas opciones que `column` en el DSL.

`CsvImporter::Importer.new(file_path, model, **opciones)`:

| Opción | Descripción |
|---|---|
| `columns:` | Lista de `Column` (obligatoria). |
| `find_by:` | Lista de atributos, como `find_by` en el DSL. |
| `csv:` | Hash con las opciones de `csv` (`col_sep:`, `encoding:`, `headers:`, `skip_lines:`). |
| `defaults:`, `after_map:` | Como en `Base#new`. `after_map:` acepta uno o una lista. |
| `atomic:`, `bulk:`, `batch_size:` | Como en `Base#new`. |

Devuelve el mismo `CsvImporter::Result` al llamar a `call`.

## Errores

| Excepción | Cuándo |
|---|---|
| `CsvImporter::ConfigurationError` | La clase está mal declarada (sin `model`, sin columnas, `find_by` con atributos que no son columnas, opciones de `csv` inválidas, `after_map` sin `call`) o falta el índice único en modo masivo. |
| `CsvImporter::InvalidHeaderError` | Faltan headers declarados en el CSV (o en `headers:`). |
| `CsvImporter::InvalidFileError` | El archivo no se puede leer: CSV mal formado (comillas sin cerrar), codificación distinta de la indicada o bytes que no existen en ella. El mensaje dice la línea y, si es la codificación, cómo indicarla. |
| `ArgumentError` | Un `type:` desconocido al declarar una columna. |

Los problemas de datos (celdas vacías obligatorias, valores que no se pueden
convertir, validaciones del modelo) **no lanzan excepciones**: aparecen en
`result.errors`.

## Rendimiento

Importar 50.000 filas en SQLite en memoria, con índice único en `email`:

| Escenario | Fila a fila | `bulk: true` |
|---|---|---|
| Crear | 8,5 s · 150.050 consultas | 2,6 s · 100 consultas |
| Reimportar (todo se actualiza) | 4,0 s · 50 consultas | 1,8 s · 100 consultas |
| Crear, atómico | 6,4 s · 50.052 consultas | 1,7 s · 102 consultas |

Los tiempos son orientativos y dependen de la máquina. Compara proporciones, no
valores absolutos. Con una base de datos en red (PostgreSQL, por ejemplo), la
reducción de consultas pesa bastante más que aquí.

**Pon un índice en las columnas de `find_by`.** Sin él, cada búsqueda recorre la
tabla: en las mediciones, la importación con `find_by` fue 3,5 veces más lenta.
Un índice único además evita duplicados cuando hay importaciones concurrentes.

Para repetir las mediciones:

```bash
bundle exec ruby benchmark/import_benchmark.rb [filas]
```

## Limitaciones conocidas

- Un archivo ilegible se detecta al llegar a la línea dañada. Sin `atomic: true`,
  las filas anteriores ya se habrán guardado cuando se lance
  `CsvImporter::InvalidFileError`. Con `atomic: true` no queda nada guardado.
- `skip_lines:` cuenta líneas físicas, sin interpretar comillas.
- Una celda vacía se convierte en `nil` y, al actualizar con `find_by`, **sobrescribe**
  el valor existente.
- Con `find_by` de varias columnas, la búsqueda en modo normal se hace fila a fila
  (la precarga por lote solo se aplica a una única clave).
- Cada fila reporta como mucho un error de conversión: el primero que encuentra.

## Desarrollo

```bash
bundle install
bundle exec rspec
```

La estructura interna, de menor a mayor nivel: `Parser` (archivo a filas),
`RowMapper` y `Column` (fila a atributos, `defaults:` y `after_map`), `RecordPersister` / `BulkPersister`
(atributos a base de datos, intercambiables), `Importer` (orquesta) y `Base`
(el DSL).

## Licencia

MIT.