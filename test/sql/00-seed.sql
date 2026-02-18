-- ============================================================
-- 00-seed.sql  —  Test data (run after CREATE EXTENSION pg_fsql)
-- ============================================================
\set ON_ERROR_STOP on

-- Params for parameterized execution (_exec_templ)
INSERT INTO fsql.params (key_param, type_param) VALUES
    ('none',    'text'),
    ('date',    'date'),
    ('id',      'bigint'),
    ('name',    'text'),
    ('status',  'text'),
    ('amount',  'numeric'),
    ('flag',    'boolean')
ON CONFLICT (key_param) DO NOTHING;

-- exec: execute SQL, return jsonb
INSERT INTO fsql.templates (path, cmd, body, cached) VALUES
    ('demo_count', 'exec',
     'SELECT jsonb_build_object(''total'', count(*)) FROM {d[src]} WHERE {d[filter]}',
     false)
ON CONFLICT (path) DO NOTHING;

-- NULL (fragment): text substituted into parent as {d[child_name]}
-- exec with children
INSERT INTO fsql.templates (path, cmd, body) VALUES
    ('demo_insert', 'exec',
     'CREATE TEMP TABLE IF NOT EXISTS {d[target]} AS SELECT {d[cols]} FROM {d[src]} {d[where]}'),
    ('demo_insert.cols',  NULL, '*'),
    ('demo_insert.src',   NULL, 'pg_class'),
    ('demo_insert.where', NULL, 'WHERE relkind = {d[kind]!r}')
ON CONFLICT (path) DO NOTHING;

-- ref: redirect to another template
INSERT INTO fsql.templates (path, cmd, body) VALUES
    ('demo_ref', 'ref', 'demo_count')
ON CONFLICT (path) DO NOTHING;

-- if: conditional branching
INSERT INTO fsql.templates (path, cmd, body) VALUES
    ('demo_if',         'if', 'SELECT {d[mode]!r}'),
    ('demo_if.fast',    NULL, 'index scan'),
    ('demo_if.slow',    NULL, 'seq scan'),
    ('demo_if.default', NULL, 'auto')
ON CONFLICT (path) DO NOTHING;

-- exec with defaults
INSERT INTO fsql.templates (path, cmd, body, defaults) VALUES
    ('demo_defaults', 'exec',
     'SELECT jsonb_build_object(''msg'', {d[greeting]!r} || '' '' || {d[target]!r})',
     '{"greeting":"hello","target":"world"}')
ON CONFLICT (path) DO NOTHING;

\echo 'Seed data loaded'
