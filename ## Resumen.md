## Resumen

Versión 0.2.0 de `csv_importer`: añade lo que falta para importar extractos
bancarios en Tholos, según ADR-0017 §A y TSK-0001. Todas las capacidades son
genéricas; ninguna sabe nada de Tholos.

## Cambios

### Formato del archivo
- `csv col_sep:, encoding:, headers:, skip_lines:` en el DSL, o `csv: {...}` en `Importer`.
- `encoding: "Windows-1252"` convierte a UTF-8 al leer (equivale a `"Windows-1252:UTF-8"`).
- `headers:` es para archivos sin fila de títulos: los `header:` de las columnas se
  refieren a esos nombres y el primer registro es la línea 1.
- `skip_lines:` salta las líneas previas, y los números de línea siguen siendo los del archivo.
- Las opciones desconocidas o inválidas lanzan `ConfigurationError` al declarar la clase.

### Errores de lectura
- Nuevo `CsvImporter::InvalidFileError` para:
  - CSV mal formado;
  - texto que no está en la codificación indicada;
  - bytes que no existen en esa codificación.
- El mensaje da la línea real y sugiere `encoding:`.
- Solo se traducen los errores de lectura; los de quien consume las filas
  (por ejemplo, la base de datos) pasan tal cual.

### Valores fijos y gancho por fila
- `defaults:`, por ejecución: el CSV no puede sobrescribirlos, ni aunque haya
  una columna declarada con el mismo nombre.
- `after_map`:
  - Puede ir en la clase (bloque u objeto con `call`) o por ejecución.
  - Orden: columnas → `defaults` → ganchos de la clase → gancho de la llamada.
  - Puede modificar `attributes` en sitio o devolver un `Hash`.
  - Un `ConversionError` dentro cuenta como error de esa fila; cualquier otra
    excepción se propaga.

### API pública y documentación
- `Importer` y `Column` documentados para construir importadores sin DSL
  (perfiles guardados, US-0601).
- Instalación con `github:` + `tag:`, no con `path:`.

### Limpieza
- `spec.files` se asigna una sola vez en el gemspec.
- `pkg/csv_importer-0.1.0.gem` sale de git; se añade `.gitignore`.
- `.rubocop.yml` con Ruby 3.4 como versión, y specs excluidos de `Metrics/BlockLength`.

## Compatibilidad
Sin cambios de comportamiento para quien no use las opciones nuevas: los números
de línea, los tipos y los errores siguen igual. El único spec existente que cambia
es el de `RowMapper`, que es interno y ahora necesita llaves en el hash.

## Notas
- Sin `atomic: true`, un archivo dañado a mitad deja guardadas las filas
  anteriores a la línea dañada. Está documentado en "Limitaciones conocidas";
  Tholos usa el modo atómico.
- `rake` sigue marcando 10 avisos de RuboCop que ya existían (benchmark,
  `BulkPersister`, una línea de `base_spec`). Ninguno está en código de este PR.

## Pruebas
- `bundle exec rspec`: 67 ejemplos, 0 fallos (39 nuevos).
- Ficheros sintéticos con datos inventados en `spec/fixtures/`: formato Sabadell
  (Windows-1252, `|`, sin títulos) y uno con `;` y dos líneas previas.
- `gem build` incluye solo `lib/`, README, LICENSE y CHANGELOG.

## Después de fusionar
- Etiqueta `v0.2.0` y publicar la release.
- En Tholos: `gem "csv_importer", github: "cybertarius-code/csv_importer", tag: "v0.2.0"`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
