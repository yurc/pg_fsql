-- ============================================================
-- 09-explain.sql  —  Step-by-step template expansion trace
-- ============================================================

CREATE OR REPLACE FUNCTION fsql.explain(
    _path  text,
    _data  jsonb DEFAULT '{}'::jsonb,
    _depth int   DEFAULT 0
) RETURNS SETOF fsql.explain_step
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    _t      record;
    _r      record;
    _step   int := 0;
    _jchild jsonb := '{}'::jsonb;
    _tmp    text;
BEGIN
    SELECT path, cmd, body, defaults,
           coalesce(defaults, '{}')::jsonb || _data AS jdata
    FROM   fsql.templates
    WHERE  path = _path
    INTO   _t;

    IF _t IS NULL THEN
        _step := _step + 1;
        RETURN QUERY SELECT _step, _path, 'NOT FOUND'::text,
                            ''::text, _depth;
        RETURN;
    END IF;

    /* Emit this node */
    _step := _step + 1;
    RETURN QUERY SELECT _step, _t.path::text, coalesce(_t.cmd, 'fragment')::text,
                        fsql._c_render(coalesce(_t.body, ''), _t.jdata),
                        _depth;

    /* Follow templ redirect */
    IF _t.cmd IN ('templ', 'templ_key') THEN
        RETURN QUERY SELECT * FROM fsql.explain(_t.body, _t.jdata, _depth + 1);
        RETURN;
    END IF;

    /* Recurse into children */
    FOR _r IN
        SELECT *
        FROM   fsql.templates
        WHERE  path LIKE _path || '.%'
          AND  SPLIT_PART(replace(path, _path, ''), '.', 3) = ''
        ORDER  BY path
    LOOP
        RETURN QUERY SELECT *
            FROM fsql.explain(
                _r.path,
                _t.jdata || coalesce(_r.defaults, '{}')::jsonb,
                _depth + 1);
    END LOOP;
END;
$$;

COMMENT ON FUNCTION fsql.explain IS
'Trace the template expansion step-by-step without executing. '
'Shows rendered SQL at each node.';
