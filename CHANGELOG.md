# Changelog

## [0.2.0] - 2026-11-19

### Añadido
- Formato del archivo con `csv` en el DSL (o `csv:` en `Importer`): `col_sep:`, `encoding:`
  (una codificación distinta de UTF-8 se convierte a UTF-8 al leer), `headers:` para archivos
  sin fila de títulos y `skip_lines:` para las líneas previas a los títulos.
- `CsvImporter::InvalidFileError`: un CSV mal formado o con otra codificación da un error claro,
  con la línea, en lugar de una excepción de `csv` sin capturar.
- `defaults:`: valores fijos por fila que el CSV no puede sobrescribir.
- `after_map`: gancho por fila, en el DSL y por ejecución, con `(attributes, raw_row)`. Un
  `ConversionError` lanzado dentro cuenta como error de esa fila.
- `Importer` y `Column` documentados como API pública.

### Cambiado
- `line` en los errores es la línea del archivo: cuenta `skip_lines:` y, con `headers:`, el
  primer registro es la línea 1. Sin esas opciones no cambia.
- La instalación recomendada es desde GitHub con `tag:`.

### Corregido
- El gemspec asignaba `spec.files` dos veces.
- `pkg/` ya no se versiona.

## [0.1.0] - 2026-10-26

### Añadido
- DSL declarativo: `model`, `column` (`header`, `type`, `required`, `transform`) y `find_by`.
- Tipos: `string`, `integer`, `decimal`, `date`, `boolean`, y registro de tipos propios.
- Errores por fila sin detener la importación.
- Modo atómico (`atomic: true`).
- Procesamiento por lotes con precarga de registros existentes.
- Modo masivo opcional (`bulk: true`) con `insert_all` / `upsert_all`.