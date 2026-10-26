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

- DSL declarativo: `model`, `column` y `find_by`.
- Conversión de tipos y transformaciones por columna.
- Las filas inválidas no detienen la importación: se acumulan con su número de fila.
- Modo atómico: todo o nada, con transacción.
- Procesamiento por lotes, con memoria acotada aunque el archivo sea enorme.
- Modo masivo opcional (`insert_all` / `upsert_all`) para archivos grandes.
- Seguro por defecto: solo se escriben las columnas declaradas.

## Instalación

Mientras no esté publicada, desde una ruta local, en el `Gemfile` de la aplicación:

```ruby
gem "csv_importer", path: "../csv_importer"
```

Luego `bundle install`.

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

### Herencia

Una subclase hereda la configuración y puede ampliarla o redefinir columnas sin
afectar a la clase padre:

```ruby
class AdminUserImporter < UserImporter
  column :role # se añade solo a este importador
end
```

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

`line` es el número de registro del CSV, contando la cabecera como 1.

## Opciones

```ruby
UserImporter.new(path, atomic: true, bulk: true, batch_size: 500).call
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

## Errores

| Excepción | Cuándo |
|---|---|
| `CsvImporter::ConfigurationError` | La clase está mal declarada (sin `model`, sin columnas, `find_by` con atributos que no son columnas) o falta el índice único en modo masivo. |
| `CsvImporter::InvalidHeaderError` | Faltan headers declarados en el CSV. |
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

- Solo CSV separado por comas y codificado en UTF-8 (con o sin BOM). Los CSV
  separados por punto y coma, habituales al exportar desde Excel en configuración
  regional española, no están soportados todavía.
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
`RowMapper` y `Column` (fila a atributos), `RecordPersister` / `BulkPersister`
(atributos a base de datos, intercambiables), `Importer` (orquesta) y `Base`
(el DSL).

## Licencia

MIT.