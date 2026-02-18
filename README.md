# pg_fsql

Recursive SQL template engine for PostgreSQL.

Hierarchical template composition and execution — pure C + PL/pgSQL, no plpython3u.

## Features

- **C renderer** — fast `{d[key]}` / `{d[key]!r}` placeholder substitution
- **SPI plan cache** — optional per-template prepared plan caching
- **Recursive engine** — hierarchical dot-path templates with parent-child composition
- **6 cmd types** — `exec`, `ref`, `if`, `exec_tpl`, `map`, `NULL`
- **Safe execution** — parameterized queries via `fsql.params` type catalog
- **No superuser** — `superuser = false`, safe for shared hosting
- **Debug trace** — `RAISE NOTICE` logging with `_debug = true`
- **Legacy compatible** — old `data_algorithms` names still work

## Quick Start

```bash
# Build & install
cd pg_fsql
make && sudo make install

# Create extension
psql -d mydb -c "CREATE EXTENSION pg_fsql;"
```

```sql
-- Define a template
INSERT INTO fsql.templates (path, cmd, body) VALUES
    ('user_count', 'exec',
     'SELECT jsonb_build_object(''total'', count(*)) FROM users WHERE status = {d[status]!r}');

-- Run it
SELECT fsql.run('user_count', '{"status":"active"}');
-- {"total": 42}

-- Preview generated SQL (dry-run)
SELECT fsql.render('user_count', '{"status":"active"}');
-- SELECT jsonb_build_object('total', count(*)) FROM users WHERE status = 'active'
```

## Requirements

- PostgreSQL 14+ (tested on 17.8)
- `plpgsql` (included by default)
- Build: `gcc`, `make`, `postgresql-server-dev-XX`

## Installation

### Linux

```bash
# Ubuntu / Debian
sudo apt-get install gcc make postgresql-server-dev-17

# RHEL / CentOS
sudo yum install gcc make postgresql17-devel

cd pg_fsql/
make PG_CONFIG=/usr/bin/pg_config
sudo make install PG_CONFIG=/usr/bin/pg_config
psql -d mydb -c "CREATE EXTENSION pg_fsql;"
```

### Docker

```bash
docker cp pg_fsql postgres:/tmp/pg_fsql/
docker exec postgres bash -c "cd /tmp/pg_fsql && make install"
docker exec postgres psql -U postgres -d mydb -c "CREATE EXTENSION pg_fsql;"
```

### Verify

```sql
SELECT fsql._c_render('hello {d[name]}', '{"name":"world"}'::jsonb);
-- hello world
```

## Schema

```sql
fsql.templates (
    path      varchar(500) PRIMARY KEY,   -- dot-separated hierarchy
    cmd       varchar(50),                -- exec | ref | if | exec_tpl | map | NULL
    body      text,                       -- SQL template or target path
    defaults  text,                       -- JSON defaults
    cached    boolean DEFAULT false       -- enable SPI plan caching
)

fsql.params (
    key_param   varchar(255) PRIMARY KEY, -- parameter name
    type_param  varchar(255) NOT NULL     -- PostgreSQL cast type
)
```

## Command Types

| cmd | Action | body contains |
|-----|--------|---------------|
| `NULL` | Text fragment, substituted into parent as `{d[child_name]}` | Raw text |
| `exec` | Execute SQL, return jsonb | SQL returning jsonb |
| `ref` | Redirect to another template | Target path |
| `if` | Conditional branch — evaluate body, pick child by result | SQL returning branch name |
| `exec_tpl` | Execute SQL, then re-render result as template | SQL |
| `map` | Collect children into JSON object | Template body |

Legacy aliases: `exejson` = `exec`, `templ` = `ref`, `json` = `map`, `exejsontp` = `exec_tpl`

## Template Hierarchy

Templates form a tree via dot-separated paths:

```
report                    ← root (cmd=exec)
  report.columns          ← fragment (cmd=NULL, body='id, name')
  report.source           ← fragment (cmd=NULL, body='orders')
  report.filter           ← redirect (cmd=ref, body='common_filter')
```

Direct children: `path LIKE 'parent.%'` with exactly one extra dot-level.
Child values merge into parent data as `{d[child_name]}`.

## Placeholders

| Syntax | Behavior |
|--------|----------|
| `{d[key]}` | Replace with value (`NULL` → `null`) |
| `{d[key]!r}` | Replace with `quote_literal(value)` (`NULL` → `''`) |

Values containing `{d[...]}` are substituted first (nested expansion).

## Functions

### Core (internal)

| Function | Description |
|----------|-------------|
| `fsql._c_render(template, data)` | C placeholder substitution |
| `fsql._c_execute(sql, params, use_cache)` | SPI execution with plan caching |
| `fsql._exec_templ(templ, data, cached)` | Parameterized execution via `fsql.params` |
| `fsql._process(path, data, debug, depth)` | Recursive template engine |

### Public API

| Function | Description |
|----------|-------------|
| `fsql.run(path, data, debug)` | Execute template tree → jsonb |
| `fsql.render(path, data)` | Dry-run: render SQL without executing |
| `fsql.tree(path)` | Show template hierarchy |
| `fsql.explain(path, data)` | Step-by-step expansion trace |
| `fsql.validate()` | Check all templates for errors |
| `fsql.depends_on(path)` | List recursive dependencies |
| `fsql.clear_cache()` | Free all cached SPI plans |

## Examples

### Basic exec

```sql
INSERT INTO fsql.templates (path, cmd, body) VALUES
    ('user_count', 'exec',
     'SELECT jsonb_build_object(''total'', count(*)) FROM users WHERE status = {d[status]!r}');

SELECT fsql.run('user_count', '{"status":"active"}');
-- {"total": 42}
```

### Template with children

```sql
INSERT INTO fsql.templates (path, cmd, body) VALUES
    ('report', 'exec',
     'SELECT jsonb_build_object(''data'', array_agg(row_to_json(t)))
      FROM (SELECT {d[cols]} FROM {d[src]} {d[where]}) t'),
    ('report.cols',  NULL, 'id, name, email'),
    ('report.src',   NULL, 'customers'),
    ('report.where', NULL, 'WHERE city = {d[city]!r}');

SELECT fsql.run('report', '{"city":"Moscow"}');
```

### Conditional branching

```sql
INSERT INTO fsql.templates (path, cmd, body) VALUES
    ('greeting',         'if', 'SELECT {d[lang]!r}'),
    ('greeting.en',      NULL, 'Hello'),
    ('greeting.ru',      NULL, 'Привет'),
    ('greeting.default', NULL, 'Hi');

SELECT fsql.run('greeting', '{"lang":"ru"}');
-- {"key": "Привет"}
```

### Template reference

```sql
INSERT INTO fsql.templates (path, cmd, body) VALUES
    ('my_report', 'ref', 'report');

SELECT fsql.run('my_report', '{"city":"SPb"}');
```

### Inspect & validate

```sql
SELECT * FROM fsql.tree('report');
SELECT * FROM fsql.explain('report', '{"city":"Moscow"}');
SELECT * FROM fsql.validate();
SELECT * FROM fsql.depends_on('report');
```

### Debug trace

```sql
SELECT fsql.run('report', '{"city":"Moscow"}', true);
-- NOTICE:  [fsql] report (cmd=exec)
-- NOTICE:    exec → SELECT ...
-- NOTICE:    result → {"data": [...]}
```

## Configuration

| GUC | Type | Default | Description |
|-----|------|---------|-------------|
| `fsql.max_depth` | int | 64 | Max recursion depth |
| `fsql.cache_plans` | bool | true | Global SPI plan cache switch |

```sql
SET fsql.max_depth = 128;
SET fsql.cache_plans = false;
```

GUC variables load on first C function call (`_PG_init`).
For session-start availability, add to `postgresql.conf`:

```
shared_preload_libraries = 'pg_fsql'
```

## Plan Caching

### Problem

Every `fsql.run()` call on an `exec` template generates SQL, prepares a plan,
executes it, and discards the plan. For hot-path templates called repeatedly
with the same structure, the `SPI_prepare` overhead is wasted work.

### Solution

Two-level opt-in caching:

```
fsql.cache_plans = true     (GUC — global switch, default on)
    AND
templates.cached = true     (per-template, default off)
    →
plan is cached in a backend-local hash table
```

When both conditions are true, `_c_execute` stores the prepared plan
via `SPI_keepplan()`. Subsequent calls with the same SQL text reuse
the cached plan — only `SPI_execute_plan` runs, skipping parse/plan.

### What gets cached

`_exec_templ` renders a template into parameterized SQL:

```
Template:   SELECT ... FROM {d[src]} WHERE id = {d[id]}
                            ↑ inlined              ↑ becomes $1[N]::bigint

Result SQL: SELECT ... FROM orders WHERE id = $1[2]::bigint
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                     cache key = hash of this SQL text
```

- **Inlined values** (not in `fsql.params`) become part of the SQL text
- **Parameterized values** (in `fsql.params`) become `$1[N]::type` — do not affect the plan
- **Cache key** = `hash_any_extended(sql_text)` — uint64, collision-free for practical sizes

| Scenario | Cache |
|----------|-------|
| Same template, same inline data, different param values | **HIT** |
| Same template, different inline data | **MISS** — different SQL |
| Different templates | **MISS** — different SQL |

### Usage

```sql
-- Enable for hot templates
UPDATE fsql.templates SET cached = true WHERE path = 'my_template';

-- Calls are transparent — caching is automatic
SELECT fsql.run('my_template', '{"id":"1"}');  -- prepare + cache
SELECT fsql.run('my_template', '{"id":"2"}');  -- cache hit

-- After DDL changes, flush stale plans
SELECT fsql.clear_cache();

-- Disable globally for debugging
SET fsql.cache_plans = false;
```

### When to enable

| Use case | cached | Why |
|----------|--------|-----|
| Frequently called, stable inline data | **true** | Saves `SPI_prepare` on every call |
| User-supplied `{d[key]!r}` values | **false** | Every call = different SQL, no reuse |
| Called once per session | **false** | No benefit |
| Hot path in loop / batch | **true** | Maximum effect |

### When to call clear_cache()

- After DDL: `ALTER TABLE`, `DROP INDEX`, `CREATE VIEW`, etc.
- After updating `fsql.params` (type changes → different SQL)
- After modifying `body` of templates with `cached = true`
- On suspected stale plan (unexpectedly slow query)

## Migration from data_algorithms

```sql
-- Copy templates
INSERT INTO fsql.templates (path, cmd, body, defaults)
SELECT path, cmd, stempl, mask_before
FROM   data_algorithms.c_sql_templ
WHERE  path IS NOT NULL
ON CONFLICT (path) DO UPDATE SET
    cmd = EXCLUDED.cmd, body = EXCLUDED.body, defaults = EXCLUDED.defaults;

-- Copy params
INSERT INTO fsql.params (key_param, type_param)
SELECT key_param, type_param FROM data_algorithms.c_params
ON CONFLICT (key_param) DO UPDATE SET type_param = EXCLUDED.type_param;

-- Optional: compatibility wrappers
CREATE FUNCTION data_algorithms.f_template_load_sql(_t text, _d jsonb)
RETURNS text LANGUAGE sql STABLE AS $$ SELECT fsql._c_render(_t, _d) $$;

CREATE FUNCTION data_algorithms.f_sql(_p text, _d jsonb DEFAULT '{}', _dbg boolean DEFAULT false)
RETURNS SETOF jsonb LANGUAGE sql VOLATILE AS $$ SELECT fsql._process(_p, _d, _dbg, 0) $$;
```

## Testing

```bash
# Run full test suite (inside PostgreSQL container or host)
psql -d test_db -f test/sql/00-seed.sql
psql -d test_db -f test/sql/01-render.sql
psql -d test_db -f test/sql/02-process.sql
psql -d test_db -f test/sql/03-render-tree-validate.sql
psql -d test_db -f test/sql/06-cache.sql

# Or use the runner
cd test && bash run_tests.sh
```

## File Structure

```
pg_fsql/
├── src/
│   ├── pg_fsql.c            _PG_init, GUC definitions
│   ├── render.c             C renderer: {d[key]} substitution
│   └── execute.c            SPI plan cache: _c_execute, clear_cache
├── sql/parts/
│   ├── 00-types.sql         composite types
│   ├── 01-tables.sql        templates, params tables
│   ├── 02-indexes.sql       indexes
│   ├── 03-cfuncs.sql        C function declarations
│   ├── 04-exec-templ.sql    parameterized execution
│   ├── 05-process.sql       recursive engine
│   ├── 06-run.sql           public API: run()
│   ├── 07-render.sql        dry-run rendering
│   ├── 08-tree.sql          tree visualization
│   ├── 09-explain.sql       expansion trace
│   ├── 10-validate.sql      template validation
│   ├── 11-depends-on.sql    dependency analysis
│   └── 99-compat.sql        migration notes
├── test/
│   ├── run_tests.sh         test runner
│   └── sql/
│       ├── 00-seed.sql      test fixtures
│       ├── 01-render.sql    _c_render tests
│       ├── 02-process.sql   _process + run tests
│       ├── 03-render-tree-validate.sql
│       ├── 04-migration.sql data_algorithms migration
│       ├── 05-gen-select.sql
│       └── 06-cache.sql     SPI plan cache tests
├── Makefile
├── pg_fsql.control
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## License

Released under the [PostgreSQL License](LICENSE).
