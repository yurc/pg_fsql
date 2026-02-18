-- ============================================================
-- 05-process.sql  —  Recursive template engine (_process)
-- ============================================================
-- cmd types:
--   NULL      — text fragment, returned as {"key": rendered_text}
--   exec      — execute SQL, return jsonb result
--   ref       — redirect to another template (body = target path)
--   if        — conditional branch (body = SQL returning branch name)
--   exec_tpl  — execute SQL, then re-render result through _c_render
--   map       — collect children into a JSON object
--
-- Legacy aliases (for migration compatibility):
--   exejson   → exec
--   exejsontp → exec_tpl
--   templ     → ref
--   json      → map
-- ============================================================

CREATE OR REPLACE FUNCTION fsql._process(
    _path   text,
    _jdata  jsonb   DEFAULT '{}'::jsonb,
    _debug  boolean DEFAULT false,
    _depth  int     DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    _t       record;
    _r       record;
    _str     text := '';
    _jchild  jsonb;
    _tmp     jsonb;
    _max_d   int;
    _pad     text;
    _sql     text;
    _cmd     text;
BEGIN
    /* ---- recursion guard ---- */
    _max_d := coalesce(
        current_setting('fsql.max_depth', true)::int, 64);
    IF _depth > _max_d THEN
        RAISE EXCEPTION 'fsql: max recursion depth (%) exceeded at path: %',
            _max_d, _path;
    END IF;

    _pad := repeat('  ', _depth);

    /* ---- load template ---- */
    SELECT path, cmd, body, defaults, cached,
           coalesce(defaults, '{}')::jsonb || _jdata AS jdata
    FROM   fsql.templates
    WHERE  path = _path
    INTO   _t;

    IF _t IS NULL THEN
        IF _debug THEN
            RAISE NOTICE '%[fsql] % → NOT FOUND', _pad, _path;
        END IF;
        RETURN '{}'::jsonb;
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

    IF _debug THEN
        RAISE NOTICE '%[fsql] % (cmd=%)', _pad, _path, coalesce(_cmd, 'NULL');
    END IF;

    /* ---- IF: conditional branching ---- */
    IF _cmd = 'if' THEN
        _sql := fsql._c_render(_t.body, _t.jdata);
        EXECUTE _sql INTO _str;
        IF _debug THEN
            RAISE NOTICE '%  if → condition=% branch=%', _pad, _sql, _str;
        END IF;
        IF EXISTS (SELECT 1 FROM fsql.templates
                   WHERE path = _t.path || '.' || _str) THEN
            RETURN fsql._process(
                _t.path || '.' || _str, _t.jdata, _debug, _depth + 1);
        ELSE
            IF _debug THEN
                RAISE NOTICE '%  if → branch "%" not found, using default', _pad, _str;
            END IF;
            RETURN fsql._process(
                _t.path || '.default', _t.jdata, _debug, _depth + 1);
        END IF;
    END IF;

    /* ---- collect children ---- */
    _jchild := '{}'::jsonb;

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
            _debug,
            _depth + 1
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

    /* ---- produce result based on cmd ---- */
    IF _cmd IN ('exec', 'exejson') THEN
        _sql := fsql._c_render(_t.body, _t.jdata || _jchild);
        IF _debug THEN
            RAISE NOTICE '%  exec → %', _pad, left(_sql, 200);
        END IF;
        _tmp := fsql._exec_templ(_t.body, _t.jdata || _jchild, _t.cached);
        IF _debug THEN
            RAISE NOTICE '%  result → %', _pad, left(_tmp::text, 200);
        END IF;
        RETURN coalesce(_tmp, '{}'::jsonb);

    ELSIF _cmd IN ('exec_tpl', 'exejsontp') THEN
        _sql := fsql._c_render(_t.body, _t.jdata || _jchild);
        IF _debug THEN
            RAISE NOTICE '%  exec_tpl → %', _pad, left(_sql, 200);
        END IF;
        _tmp := fsql._c_render(
            fsql._exec_templ(_t.body, _t.jdata || _jchild, _t.cached)::text,
            _t.jdata || _jchild
        )::jsonb;
        IF _debug THEN
            RAISE NOTICE '%  result → %', _pad, left(_tmp::text, 200);
        END IF;
        RETURN _tmp;

    ELSIF _cmd IN ('ref', 'templ') THEN
        IF _debug THEN
            RAISE NOTICE '%  ref → %', _pad, _t.body;
        END IF;
        RETURN fsql._process(
            _t.body, _t.jdata || _jchild, _debug, _depth + 1);

    ELSIF _cmd IN ('map', 'json') THEN
        _tmp := jsonb_build_object(
            _t.path,
            fsql._c_render(_t.body, _t.jdata || _jchild));
        IF _debug THEN
            RAISE NOTICE '%  map → %', _pad, left(_tmp::text, 200);
        END IF;
        RETURN _tmp;

    ELSIF _t.body IS NOT NULL THEN
        _str := fsql._c_render(_t.body, _t.jdata || _jchild);
        IF _debug THEN
            RAISE NOTICE '%  fragment → %', _pad, left(_str, 200);
        END IF;
        RETURN jsonb_build_object('key', _str);

    ELSE
        IF _debug THEN
            RAISE NOTICE '%  children → %', _pad, left(_jchild::text, 200);
        END IF;
        RETURN coalesce(_jchild, '{}'::jsonb);
    END IF;
END;
$$;

COMMENT ON FUNCTION fsql._process IS
'Recursive template engine. cmd: exec, ref, if, exec_tpl, map, NULL. '
'Legacy aliases (exejson, templ, json, etc.) supported. Use _debug=true for NOTICE log. '
'Templates with cached=true use SPI plan caching (see fsql.cache_plans GUC).';
