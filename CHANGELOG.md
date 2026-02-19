# Changelog

## 1.1.0 — 2026-02-19

### Added
- `{d[key]!j}` format — jsonb literal substitution: `'<value>'::jsonb` (strings auto-quoted, objects/arrays pass through)
- `{d[key]!i}` format — `quote_identifier` substitution for safe SQL identifiers (reserved words get quoted)
- `_self` virtual key — injects the full input JSON when `{d[_self]}` or `{d[_self]!j}` appears in template body
- `render()` now executes children via `_process` — dry-run resolves child dependencies before rendering parent SQL
- REST CRUD test (`07-rest-crud.sql`) — demonstrates dynamic UPDATE with `_self!j` + `jsonb_populate_record`

### Fixed
- `validate()` orphan check now correctly scopes to fragments (`cmd IS NULL`) only

## 1.0.0 — 2026-02-18

### Added
- C-based `{d[key]}` / `{d[key]!r}` renderer (`_c_render`)
- SPI plan caching with per-template opt-in (`cached` column + `fsql.cache_plans` GUC)
- `_c_execute(sql, params, use_cache)` — SPI execution with optional plan caching
- `clear_cache()` — free all cached prepared plans
- Recursive template engine (`_process`) with 6 cmd types: `exec`, `ref`, `if`, `exec_tpl`, `map`, `NULL`
- Public API: `run()`, `render()`, `tree()`, `explain()`, `validate()`, `depends_on()`
- Safe parameterized execution via `fsql.params` type catalog
- Legacy alias support (`exejson`, `templ`, `json`, `exejsontp`)
- Migration path from `data_algorithms` schema
- Full test suite (7 test files)
