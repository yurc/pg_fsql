-- ============================================================
-- 07-render.sql  —  Dry-run: execute children, render parent
-- ============================================================
-- render = "покажи SQL который run выполнил бы"
-- Children с cmd=exec выполняются (нужны реальные данные),
-- но сам parent только рендерится в текст, без EXECUTE.
-- ============================================================

CREATE OR REPLACE FUNCTION fsql.render(
    _path  text,
    _data  jsonb DEFAULT '{}'::jsonb
) RETURNS text
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    _t       record;
    _r       record;
    _jchild  jsonb := '{}'::jsonb;
    _tmp     jsonb;
    _cmd     text;
BEGIN
    SELECT path, cmd, body, defaults, cached,
           coalesce(defaults, '{}')::jsonb || _data AS jdata
    FROM   fsql.templates
    WHERE  path = _path
    INTO   _t;

    IF _t IS NULL THEN
        RAISE EXCEPTION 'Template not found: %', _path;
    END IF;

    /* ---- normalize legacy cmd aliases ---- */
    _cmd := CASE _t.cmd
        WHEN 'exejson'   THEN 'exec'
        WHEN 'exejsontp' THEN 'exec_tpl'
        WHEN 'templ'     THEN 'ref'
        WHEN 'templ_key' THEN 'ref'
        WHEN 'json'      THEN 'map'
        WHEN 'array'     THEN 'map'
        ELSE _t.cmd
    END;

    /* ---- ref: follow redirect, render target ---- */
    IF _cmd = 'ref' THEN
        RETURN fsql.render(_t.body, _t.jdata);
    END IF;

    /* ---- execute children via _process (real data!) ---- */
    FOR _r IN
        SELECT *
        FROM   fsql.templates
        WHERE  path LIKE _path || '.%'
          AND  SPLIT_PART(replace(path, _path, ''), '.', 3) = ''
        ORDER  BY path
    LOOP
        _tmp := fsql._process(
            _r.path,
            _t.jdata || coalesce(_r.defaults, '{}')::jsonb,
            false,
            1
        );

        _jchild := _jchild ||
            CASE
                WHEN _r.cmd IS NULL THEN
                    jsonb_build_object(
                        SPLIT_PART(_r.path::text, '.', -1),
                        _tmp ->> 'key')
                WHEN _r.cmd IN ('map', 'json', 'array') THEN
                    jsonb_build_object(
                        SPLIT_PART(_r.path::text, '.', -1),
                        _tmp || coalesce(_r.defaults, '{}')::jsonb)
                WHEN jsonb_typeof(_tmp) = 'object' THEN
                    fsql._c_render(
                        _tmp::text,
                        _t.jdata || coalesce(_r.defaults, '{}')::jsonb
                    )::jsonb
                ELSE
                    jsonb_build_object(
                        SPLIT_PART(_r.path::text, '.', -1), _tmp)
            END;
    END LOOP;

    _jchild := jsonb_strip_nulls(_jchild);

    /* ---- render parent body (NO execute) ---- */
    RETURN fsql._c_render(
        coalesce(_t.body, ''),
        _t.jdata || _jchild);
END;
$$;

COMMENT ON FUNCTION fsql.render IS
'Dry-run: execute children to resolve dependencies, then render '
'the parent SQL as text without executing it. Shows what run() would execute.';
