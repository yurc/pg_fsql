-- ============================================================
-- 01-tables.sql  —  Core tables (minimal schema)
-- ============================================================

CREATE TABLE fsql.templates (
    path        varchar(500) PRIMARY KEY,
    cmd         varchar(50),
    body        text,
    defaults    text,
    cached      boolean DEFAULT false
);

COMMENT ON TABLE  fsql.templates IS 'SQL templates with hierarchical path structure';
COMMENT ON COLUMN fsql.templates.path     IS 'Hierarchical dot-separated path (e.g. report.filter.columns)';
COMMENT ON COLUMN fsql.templates.cmd      IS 'Processing type: exec, ref, if, exec_tpl, map, NULL';
COMMENT ON COLUMN fsql.templates.body     IS 'SQL template body with {d[key]} and {d[key]!r} placeholders';
COMMENT ON COLUMN fsql.templates.defaults IS 'JSON defaults merged before user-supplied data';
COMMENT ON COLUMN fsql.templates.cached   IS 'Enable SPI plan caching for this template (requires fsql.cache_plans=true)';

CREATE TABLE fsql.params (
    key_param   varchar(255) PRIMARY KEY,
    type_param  varchar(255) NOT NULL
);

COMMENT ON TABLE  fsql.params IS 'Parameter type catalog for safe parameterized execution';
