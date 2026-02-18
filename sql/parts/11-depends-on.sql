-- ============================================================
-- 11-depends-on.sql  —  Dependency analysis
-- ============================================================

CREATE OR REPLACE FUNCTION fsql.depends_on(
    _path text
) RETURNS TABLE(dependency text, dep_type text)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE deps AS (
        /* seed: direct children + templ references */
        SELECT c.path::text AS dep_path,
               'child'::text AS dep_type
        FROM   fsql.templates c
        WHERE  c.path LIKE _path || '.%'
          AND  SPLIT_PART(replace(c.path, _path, ''), '.', 3) = ''

        UNION ALL

        SELECT t.body::text AS dep_path,
               'templ_ref'::text AS dep_type
        FROM   fsql.templates t
        WHERE  t.path = _path
          AND  t.cmd IN ('ref', 'templ', 'templ_key')
          AND  t.body IS NOT NULL

        UNION ALL

        /* recurse: children of discovered nodes + their templ refs */
        SELECT sub.dep_path::text, sub.dep_type
        FROM   deps d,
        LATERAL (
            SELECT c.path::text AS dep_path, 'child'::text AS dep_type
            FROM   fsql.templates c
            WHERE  c.path LIKE d.dep_path || '.%'
              AND  SPLIT_PART(replace(c.path, d.dep_path, ''), '.', 3) = ''

            UNION ALL

            SELECT t.body::text, 'templ_ref'::text
            FROM   fsql.templates t
            WHERE  t.path = d.dep_path
              AND  t.cmd IN ('ref', 'templ', 'templ_key')
              AND  t.body IS NOT NULL
        ) sub
    )
    SELECT DISTINCT d.dep_path, d.dep_type
    FROM   deps d
    WHERE  d.dep_path IS NOT NULL
      AND  d.dep_path <> _path
    ORDER  BY d.dep_type, d.dep_path;
END;
$$;

COMMENT ON FUNCTION fsql.depends_on IS
'List all templates that a given template depends on (children + templ references), recursively.';
