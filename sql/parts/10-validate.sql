-- ============================================================
-- 10-validate.sql  —  Template validation
-- ============================================================

CREATE OR REPLACE FUNCTION fsql.validate()
RETURNS SETOF fsql.validation_result
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    _r record;
BEGIN
    /* 1. Unknown cmd */
    FOR _r IN
        SELECT path, cmd
        FROM   fsql.templates
        WHERE  cmd IS NOT NULL
          AND  cmd NOT IN (
              'exec','ref','if','exec_tpl','map',          -- new names
              'exejson','exejsontp','templ','json',        -- legacy aliases
              'templ_key','array')                         -- deprecated (accepted)
    LOOP
        RETURN QUERY SELECT _r.path::text, 'ERROR'::text,
            format('Unknown cmd: %s', _r.cmd);
    END LOOP;

    /* 2. ref pointing to non-existent target */
    FOR _r IN
        SELECT t.path, t.body
        FROM   fsql.templates t
        WHERE  t.cmd IN ('ref', 'templ', 'templ_key')
          AND  NOT EXISTS (
              SELECT 1 FROM fsql.templates t2 WHERE t2.path = t.body)
    LOOP
        RETURN QUERY SELECT _r.path::text, 'ERROR'::text,
            format('ref target not found: %s', _r.body);
    END LOOP;

    /* 3. if-nodes without any child branches */
    FOR _r IN
        SELECT t.path
        FROM   fsql.templates t
        WHERE  t.cmd = 'if'
          AND  NOT EXISTS (
              SELECT 1 FROM fsql.templates c
              WHERE  c.path LIKE t.path || '.%'
                AND  SPLIT_PART(replace(c.path, t.path, ''), '.', 3) = '')
    LOOP
        RETURN QUERY SELECT _r.path::text, 'WARNING'::text,
            'if-node has no child branches';
    END LOOP;

    /* 4. Empty body on exec / exec_tpl */
    FOR _r IN
        SELECT path
        FROM   fsql.templates
        WHERE  cmd IN ('exec', 'exec_tpl', 'exejson', 'exejsontp')
          AND  (body IS NULL OR body = '')
    LOOP
        RETURN QUERY SELECT _r.path::text, 'ERROR'::text,
            'exec template has empty body';
    END LOOP;

    /* 5. defaults is not valid JSON */
    FOR _r IN
        SELECT path, defaults
        FROM   fsql.templates
        WHERE  defaults IS NOT NULL
          AND  defaults <> ''
    LOOP
        BEGIN
            PERFORM _r.defaults::jsonb;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT _r.path::text, 'ERROR'::text,
                format('defaults is not valid JSON: %s', left(_r.defaults, 60));
        END;
    END LOOP;

    /* 6. Orphan children */
    FOR _r IN
        SELECT c.path,
               regexp_replace(c.path, '\.[^.]+$', '') AS parent_path
        FROM   fsql.templates c
        WHERE  c.path LIKE '%.%'
          AND  NOT EXISTS (
              SELECT 1 FROM fsql.templates p
              WHERE  p.path = regexp_replace(c.path, '\.[^.]+$', ''))
    LOOP
        RETURN QUERY SELECT _r.path::text, 'WARNING'::text,
            format('Parent not found: %s', _r.parent_path);
    END LOOP;

    /* All good */
    IF NOT FOUND THEN
        RETURN QUERY SELECT ''::text, 'OK'::text,
            format('All %s templates are valid',
                   (SELECT count(*) FROM fsql.templates));
    END IF;
END;
$$;

COMMENT ON FUNCTION fsql.validate IS
'Validate all templates: unknown cmd, broken refs, missing if-branches, '
'invalid defaults, orphan children.';
