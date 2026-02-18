-- ============================================================
-- Test: Migration from data_algorithms (optional)
-- ============================================================
\set ON_ERROR_STOP on

-- Migration: copy templates (source has old column names; cached defaults to false)
INSERT INTO fsql.templates (path, cmd, body, defaults, cached)
SELECT path, cmd, stempl, mask_before, false
FROM   data_algorithms.c_sql_templ
WHERE  path IS NOT NULL
ON CONFLICT (path) DO UPDATE SET
    cmd      = EXCLUDED.cmd,
    body     = EXCLUDED.body,
    defaults = EXCLUDED.defaults;

-- Migration: copy params
INSERT INTO fsql.params (key_param, type_param)
SELECT key_param, type_param
FROM   data_algorithms.c_params
ON CONFLICT (key_param) DO UPDATE SET
    type_param = EXCLUDED.type_param;

-- Verify counts
DO $test$
DECLARE
    _src int;
    _dst int;
BEGIN
    SELECT count(*) INTO _src FROM data_algorithms.c_sql_templ WHERE path IS NOT NULL;
    SELECT count(*) INTO _dst FROM fsql.templates;
    ASSERT _dst >= _src,
        format('Templates: src=%s dst=%s', _src, _dst);

    SELECT count(*) INTO _src FROM data_algorithms.c_params;
    SELECT count(*) INTO _dst FROM fsql.params;
    ASSERT _dst >= _src,
        format('Params: src=%s dst=%s', _src, _dst);

    RAISE NOTICE 'Migration OK: % templates, % params', _dst,
        (SELECT count(*) FROM fsql.params);
END;
$test$;

-- Create compatibility wrappers
CREATE OR REPLACE FUNCTION data_algorithms.f_template_load_sql(
    _template text, _data jsonb
) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT fsql._c_render(_template, _data);
$$;

CREATE OR REPLACE FUNCTION data_algorithms.f_exetempl_sql(
    _templ text, _jsonb jsonb DEFAULT '{}'
) RETURNS jsonb LANGUAGE sql VOLATILE AS $$
    SELECT fsql._exec_templ(_templ, _jsonb);
$$;

CREATE OR REPLACE FUNCTION data_algorithms.f_sql(
    _path text, _jdata jsonb DEFAULT '{}', _debug boolean DEFAULT false
) RETURNS SETOF jsonb LANGUAGE sql VOLATILE AS $$
    SELECT fsql._process(_path, _jdata, _debug, 0);
$$;

-- Verify compatibility
DO $test$
DECLARE
    _r text;
BEGIN
    _r := data_algorithms.f_template_load_sql(
        'hello {d[name]}', '{"name":"world"}'::jsonb);
    ASSERT _r = 'hello world',
        format('Compat: got %s', _r);
    RAISE NOTICE 'Compatibility wrappers OK';
END;
$test$;
