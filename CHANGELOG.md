# Changelog

## [0.1.0] - 2026-10-26

### Añadido
- DSL declarativo: `model`, `column` (`header`, `type`, `required`, `transform`) y `find_by`.
- Tipos: `string`, `integer`, `decimal`, `date`, `boolean`, y registro de tipos propios.
- Errores por fila sin detener la importación.
- Modo atómico (`atomic: true`).
- Procesamiento por lotes con precarga de registros existentes.
- Modo masivo opcional (`bulk: true`) con `insert_all` / `upsert_all`.