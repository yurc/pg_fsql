-- ============================================================
-- 06-run.sql  —  Execute a template (public API)
-- ============================================================

CREATE OR REPLACE FUNCTION fsql.run(
    _path  text,
    _data  jsonb   DEFAULT '{}'::jsonb,
    _debug boolean DEFAULT false
) RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT fsql._process(_path, _data, _debug, 0);
$$;

COMMENT ON FUNCTION fsql.run IS
'Execute a template tree and return the result as JSONB. '
'Equivalent to data_algorithms.f_sql().';
