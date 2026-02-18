-- ============================================================
-- 03-cfuncs.sql  —  C-language function declarations
-- ============================================================

CREATE FUNCTION fsql._c_render(template text, data jsonb)
RETURNS text
AS 'MODULE_PATHNAME', 'fsql_c_render'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

COMMENT ON FUNCTION fsql._c_render IS
'Fast C implementation of {d[key]} / {d[key]!r} substitution. '
'Values containing {d[…]} are substituted first (nested expansion).';

CREATE FUNCTION fsql._c_execute(sql text, params text[], use_cache boolean DEFAULT false)
RETURNS jsonb
AS 'MODULE_PATHNAME', 'fsql_c_execute'
LANGUAGE C VOLATILE;

COMMENT ON FUNCTION fsql._c_execute IS
'Execute a parameterized SQL query via SPI. '
'When use_cache=true and fsql.cache_plans=true, the prepared plan is cached for reuse.';

CREATE FUNCTION fsql.clear_cache()
RETURNS void
AS 'MODULE_PATHNAME', 'fsql_clear_cache'
LANGUAGE C VOLATILE;

COMMENT ON FUNCTION fsql.clear_cache IS
'Free all cached SPI plans. Call after DDL changes or to reclaim memory.';
