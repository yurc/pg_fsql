-- ============================================================
-- 00-types.sql  —  Custom composite types
-- ============================================================

CREATE TYPE fsql.tree_node AS (
    path        text,
    depth       int,
    cmd         text,
    has_children boolean
);

CREATE TYPE fsql.validation_result AS (
    path    text,
    status  text,
    message text
);

CREATE TYPE fsql.explain_step AS (
    step         int,
    path         text,
    cmd          text,
    rendered_sql text,
    depth        int
);
