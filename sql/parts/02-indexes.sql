-- ============================================================
-- 02-indexes.sql  —  Indexes
-- ============================================================

CREATE INDEX idx_fsql_templates_path_pattern
    ON fsql.templates (path text_pattern_ops);
