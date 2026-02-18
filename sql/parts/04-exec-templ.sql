-- ============================================================
-- 04-exec-templ.sql  —  Parameterized SQL execution
-- ============================================================
-- Exact port of data_algorithms.f_exetempl_sql:
--   1. Looks up parameter types in fsql.params
--   2. Replaces typed keys with $1[N]::type for safe binding
--   3. Renders remaining placeholders via _c_render
--   4. Executes the query via fsql._c_execute (SPI)
--
-- Plan caching (_cached parameter):
--   When _cached=true AND GUC fsql.cache_plans=true, the
--   prepared plan is kept in a backend-local hash table and
--   reused on subsequent calls with the same SQL text.
--   The key is hash(rendered_sql), so same template+data →
--   same plan.  Parameter values ($1[N]) change per call
--   but do not affect the cached plan.
-- ============================================================

CREATE OR REPLACE FUNCTION fsql._exec_templ(
    _templ   text,
    _jsonb   jsonb   DEFAULT '{}'::jsonb,
    _cached  boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    formatted_query text;
    lvalues         text[];
    _jdata          jsonb;
BEGIN
    WITH a AS (
        SELECT p.key_param,
               j.value,
               row_number() OVER (ORDER BY p.key_param) AS num,
               p.type_param
        FROM   jsonb_each_text('{"none":null}'::jsonb || _jsonb) j
        INNER JOIN fsql.params p ON j.key = p.key_param
        ORDER  BY p.key_param
    ),
    param AS (
        SELECT
            jsonb_object(
                ARRAY_AGG(key_param),
                ARRAY_AGG(
                    CASE WHEN type_param IS NULL
                         THEN format('$1[%s]', num)
                         ELSE format('$1[%s]::%s', num, type_param)
                    END
                )
            ) AS jdata,
            ARRAY_AGG(value) AS lvalues
        FROM a
    )
    SELECT fsql._c_render(_templ, _jsonb || param.jdata),
           param.lvalues
    INTO   formatted_query, lvalues
    FROM   param;

    _jdata := fsql._c_execute(formatted_query, lvalues, _cached);
    RETURN _jdata;
END;
$$;

COMMENT ON FUNCTION fsql._exec_templ IS
'Execute a SQL template with safe parameterized binding via fsql.params type catalog. '
'When _cached=true and fsql.cache_plans=true, the SPI plan is cached for reuse.';
