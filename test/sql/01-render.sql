-- ============================================================
-- Test: fsql._c_render
-- ============================================================
\set ON_ERROR_STOP on

DO $test$
DECLARE
    _r text;
BEGIN
    -- Basic substitution
    _r := fsql._c_render(
        'SELECT * FROM {d[table]} WHERE id = {d[id]}',
        '{"table":"users","id":"42"}'::jsonb);
    ASSERT _r = 'SELECT * FROM users WHERE id = 42',
        format('Basic: got %s', _r);

    -- Quote literal (!r)
    _r := fsql._c_render(
        'SELECT * FROM t WHERE name = {d[name]!r}',
        '{"name":"O''Brien"}'::jsonb);
    ASSERT _r = 'SELECT * FROM t WHERE name = ''O''''Brien''',
        format('Quote literal: got %s', _r);

    -- NULL value
    _r := fsql._c_render(
        '{d[x]} and {d[x]!r}',
        '{"x":null}'::jsonb);
    ASSERT _r = 'null and ''''',
        format('NULL value: got %s', _r);

    -- Nested patterns
    _r := fsql._c_render(
        'SELECT {d[cols]}',
        '{"cols":"{d[a]}, {d[b]}","a":"x","b":"y"}'::jsonb);
    ASSERT _r = 'SELECT x, y',
        format('Nested: got %s', _r);

    -- Empty data
    _r := fsql._c_render('hello {d[world]}', '{}'::jsonb);
    ASSERT _r = 'hello {d[world]}',
        format('Empty data: got %s', _r);

    -- Short keys (regression: off-by-one fix)
    _r := fsql._c_render('{d[a]}', '{"a":"1"}'::jsonb);
    ASSERT _r = '1', format('Short key: got %s', _r);

    -- Numeric + boolean
    _r := fsql._c_render('{d[n]} {d[f]}', '{"n":3.14,"f":true}'::jsonb);
    ASSERT _r = '3.14 true', format('Types: got %s', _r);

    RAISE NOTICE 'All _c_render tests passed';
END;
$test$;
