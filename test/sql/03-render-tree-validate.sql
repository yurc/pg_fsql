-- ============================================================
-- Test: fsql.render, fsql.tree, fsql.validate (requires 00-seed.sql)
-- ============================================================
\set ON_ERROR_STOP on

-- Test render (dry-run)
DO $test$
DECLARE
    _r text;
BEGIN
    _r := fsql.render('demo_insert', '{"target":"tmp","kind":"r"}');
    ASSERT _r LIKE '%CREATE TEMP TABLE%tmp%',
        format('Render target: got %s', _r);
    ASSERT _r LIKE '%FROM pg_class%',
        format('Render src child: got %s', _r);
    ASSERT _r LIKE '%relkind%',
        format('Render where child: got %s', _r);
    RAISE NOTICE 'Render test passed';
END;
$test$;

-- Test tree
DO $test$
DECLARE
    _cnt int;
BEGIN
    SELECT count(*) INTO _cnt FROM fsql.tree('demo_insert');
    ASSERT _cnt = 4,
        format('Tree: expected 4 nodes, got %s', _cnt);
    RAISE NOTICE 'Tree test passed (%s nodes)', _cnt;
END;
$test$;

-- Test validate
DO $test$
DECLARE
    _errs int;
BEGIN
    SELECT count(*) INTO _errs
    FROM fsql.validate()
    WHERE status = 'ERROR';

    ASSERT _errs = 0, format('Validate: %s errors', _errs);
    RAISE NOTICE 'Validate test passed';
END;
$test$;
