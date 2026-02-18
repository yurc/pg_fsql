-- ============================================================
-- 08-tree.sql  —  Template tree visualisation
-- ============================================================

CREATE OR REPLACE FUNCTION fsql.tree(
    _root_path text DEFAULT NULL
) RETURNS SETOF fsql.tree_node
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE t AS (
        /* roots: either a specific path or all top-level templates */
        SELECT path, cmd, 0 AS depth
        FROM   fsql.templates
        WHERE  CASE
                 WHEN _root_path IS NOT NULL THEN path = _root_path
                 ELSE path NOT LIKE '%.%'
               END

        UNION ALL

        /* direct children */
        SELECT c.path, c.cmd, t.depth + 1
        FROM   t
        JOIN   fsql.templates c
          ON   c.path LIKE t.path || '.%'
         AND   SPLIT_PART(replace(c.path, t.path, ''), '.', 3) = ''
    )
    SELECT t.path,
           t.depth,
           t.cmd,
           EXISTS (
               SELECT 1 FROM fsql.templates ch
               WHERE  ch.path LIKE t.path || '.%'
                 AND  SPLIT_PART(replace(ch.path, t.path, ''), '.', 3) = ''
           ) AS has_children
    FROM   t
    ORDER  BY t.path;
$$;

COMMENT ON FUNCTION fsql.tree IS
'Show the hierarchical tree of templates starting from a root path. '
'Pass NULL to see all top-level roots.';
