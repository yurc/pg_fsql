-- ============================================================
-- 07-render.sql  —  Dry-run rendering (no execution)
-- ============================================================

CREATE OR REPLACE FUNCTION fsql.render(
    _path  text,
    _data  jsonb DEFAULT '{}'::jsonb
) RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    _t       record;
    _r       record;
    _jchild  jsonb := '{}'::jsonb;
    _tmp     text;
BEGIN
    SELECT path, cmd, body, defaults,
           coalesce(defaults, '{}')::jsonb || _data AS jdata
    FROM   fsql.templates
    WHERE  path = _path
    INTO   _t;

    IF _t IS NULL THEN
        RAISE EXCEPTION 'Template not found: %', _path;
    END IF;

    /* Recursively render children as text and merge into data */
    FOR _r IN
        SELECT *
        FROM   fsql.templates
        WHERE  path LIKE _path || '.%'
          AND  SPLIT_PART(replace(path, _path, ''), '.', 3) = ''
        ORDER  BY path
    LOOP
        _tmp := fsql.render(
            _r.path,
            _t.jdata || coalesce(_r.defaults, '{}')::jsonb);
        _jchild := _jchild || jsonb_build_object(
            SPLIT_PART(_r.path::text, '.', -1), _tmp);
    END LOOP;

    /* Follow templ / templ_key redirects */
    IF _t.cmd IN ('templ', 'templ_key') THEN
        RETURN fsql.render(_t.body, _t.jdata || _jchild);
    END IF;

    /* Render the template body with all data merged */
    RETURN fsql._c_render(
        coalesce(_t.body, ''),
        _t.jdata || _jchild);
END;
$$;

COMMENT ON FUNCTION fsql.render IS
'Render a template to SQL text without executing it (dry-run). '
'Useful for previewing generated SQL.';
