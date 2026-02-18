-- ============================================================
-- Test: fsql._process + fsql.run (requires 00-seed.sql)
-- ============================================================
\set ON_ERROR_STOP on

DO $test$
DECLARE
    _r jsonb;
BEGIN
    -- IF branching: known branch
    _r := fsql.run('demo_if', '{"mode":"fast"}');
    ASSERT _r->>'key' = 'index scan',
        format('If fast: got %s', _r);

    -- IF branching: default
    _r := fsql.run('demo_if', '{"mode":"unknown"}');
    ASSERT _r->>'key' = 'auto',
        format('If default: got %s', _r);

    -- templ redirect
    _r := fsql.run('demo_ref', '{"src":"pg_class","filter":"true"}');
    ASSERT (_r->>'total')::int > 0,
        format('Templ ref: got %s', _r);

    -- defaults
    _r := fsql.run('demo_defaults', '{}');
    ASSERT _r->>'msg' = 'hello world',
        format('Defaults: got %s', _r);

    -- defaults override
    _r := fsql.run('demo_defaults', '{"target":"pg"}');
    ASSERT _r->>'msg' = 'hello pg',
        format('Override: got %s', _r);

    RAISE NOTICE 'All _process tests passed';
END;
$test$;
