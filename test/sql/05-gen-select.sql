-- ============================================================
-- 05-gen-select.sql  —  Template: generate SELECT from table name
-- ============================================================
\set ON_ERROR_STOP on

-- Clean up
DELETE FROM fsql.templates WHERE path LIKE 'gen_select%';

-- Root: assemble SELECT {cols} FROM schema.table
INSERT INTO fsql.templates (path, cmd, body, defaults) VALUES
('gen_select', 'exec',
 'SELECT jsonb_build_object(''sql'',
    ''SELECT '' || {d[cols]!r} || '' FROM '' || quote_ident({d[schema]!r}) || ''.'' || quote_ident({d[tbl]!r}))',
 '{"schema":"public"}');

-- Child: get column list from pg_catalog with COMMENT aliases
INSERT INTO fsql.templates (path, cmd, body) VALUES
('gen_select.cols', 'exec',
 'SELECT jsonb_build_object(''cols'',
    string_agg(
        quote_ident(a.attname)
        || CASE WHEN d.description IS NOT NULL
                THEN '' AS "'' || d.description || ''"''
                ELSE ''''
           END,
        '', '' ORDER BY a.attnum))
  FROM pg_catalog.pg_attribute a
  JOIN pg_catalog.pg_class     c ON c.oid = a.attrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_catalog.pg_description d
       ON d.objoid = a.attrelid AND d.objsubid = a.attnum
  WHERE c.relname  = {d[tbl]!r}
    AND n.nspname  = {d[schema]!r}
    AND a.attnum   > 0
    AND NOT a.attisdropped');

\echo 'gen_select templates loaded'
