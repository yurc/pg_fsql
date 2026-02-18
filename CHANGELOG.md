# Changelog

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
