-- ============================================================
-- 07-rest-crud.sql  —  REST CRUD via pg_fsql templates
-- ============================================================
-- Demonstrates dynamic REST API where one set of templates
-- serves CRUD for any table.
-- Key patterns: _self!j, !r, children with cmd=exec,
-- jsonb_populate_record.
-- Prerequisites: 00-seed.sql loaded (fsql.params needed).
-- ============================================================
\set ON_ERROR_STOP on

-- ============================================================
-- 1. Setup — test table
-- ============================================================
CREATE TABLE fsql._test_orders (
    id    serial PRIMARY KEY,
    name  text,
    price numeric,
    qty   int DEFAULT 1
);

-- ============================================================
-- 2. Templates
-- ============================================================

-- POST: INSERT, return id
-- {d[name]} is parameterized via fsql.params (type=text),
-- {d[price]} is rendered directly (not in params).
INSERT INTO fsql.templates (path, cmd, body) VALUES
('rest.post', 'exec',
 'INSERT INTO {d[tbl]} (name, price) VALUES ({d[name]}, {d[price]}) RETURNING jsonb_build_object(''id'', id)');

-- GET: SELECT full row as jsonb
INSERT INTO fsql.templates (path, cmd, body) VALUES
('rest.get', 'exec',
 'SELECT to_jsonb(t) FROM {d[tbl]} t WHERE id = {d[id]}');

-- PUT: UPDATE only supplied columns via jsonb_populate_record.
-- {d[columns]} comes from child rest.put.columns (cmd=exec).
-- {d[_self]!j} - 'id' removes id key to avoid type conflict
-- with parameterized $1[N]::bigint inside jsonb literal.
INSERT INTO fsql.templates (path, cmd, body) VALUES
('rest.put', 'exec',
 'UPDATE {d[tbl]} SET ({d[columns]}) = (
    SELECT {d[columns]} FROM (
      SELECT (jsonb_populate_record(null::{d[tbl]}, {d[_self]!j} - ''id'')).*
    ) sub
  ) WHERE id = {d[id]}
  RETURNING jsonb_build_object(''id'', id)');

-- PUT child: intersect input keys with actual table columns, excluding id
INSERT INTO fsql.templates (path, cmd, body) VALUES
('rest.put.columns', 'exec',
 'SELECT jsonb_build_object(''columns'',
    string_agg(c.column_name, '','' ORDER BY c.ordinal_position))
  FROM information_schema.columns c
  WHERE c.table_schema || ''.'' || c.table_name = {d[tbl]!r}
    AND c.column_name != ''id''
    AND {d[_self]!j} ? c.column_name');

-- DELETE: remove by id
INSERT INTO fsql.templates (path, cmd, body) VALUES
('rest.delete', 'exec',
 'DELETE FROM {d[tbl]} WHERE id = {d[id]} RETURNING jsonb_build_object(''id'', id)');

\echo 'REST CRUD templates loaded'

-- ============================================================
-- 3. Tests
-- ============================================================
DO $test$
DECLARE
    _r   jsonb;
    _id  int;
    _sql text;
BEGIN
    -- --------------------------------------------------------
    -- 1. POST — insert a new order
    -- --------------------------------------------------------
    _r := fsql.run('rest.post',
        '{"tbl":"fsql._test_orders","name":"Widget","price":9.99}');
    _id := (_r->>'id')::int;
    ASSERT _id IS NOT NULL AND _id > 0,
        format('[rest 1/7] POST: expected id>0, got %s', _r);
    RAISE NOTICE '[rest 1/7] POST ok, id=%', _id;

    -- --------------------------------------------------------
    -- 2. GET — read back, verify defaults (qty=1)
    -- --------------------------------------------------------
    _r := fsql.run('rest.get',
        format('{"tbl":"fsql._test_orders","id":%s}', _id)::jsonb);
    ASSERT _r->>'name' = 'Widget',
        format('[rest 2/7] GET name: got %s', _r);
    ASSERT (_r->>'price')::numeric = 9.99,
        format('[rest 2/7] GET price: got %s', _r);
    ASSERT (_r->>'qty')::int = 1,
        format('[rest 2/7] GET qty default: got %s', _r);
    RAISE NOTICE '[rest 2/7] GET ok: name=%, price=%, qty=%',
        _r->>'name', _r->>'price', _r->>'qty';

    -- --------------------------------------------------------
    -- 3. PUT — update price and qty, name must stay unchanged
    -- --------------------------------------------------------
    _r := fsql.run('rest.put',
        format('{"tbl":"fsql._test_orders","id":%s,"price":19.99,"qty":5}', _id)::jsonb);
    ASSERT (_r->>'id')::int = _id,
        format('[rest 3/7] PUT: expected id=%, got %s', _id, _r);
    RAISE NOTICE '[rest 3/7] PUT ok: %', _r;

    -- --------------------------------------------------------
    -- 4. GET after PUT — verify updated values
    -- --------------------------------------------------------
    _r := fsql.run('rest.get',
        format('{"tbl":"fsql._test_orders","id":%s}', _id)::jsonb);
    ASSERT _r->>'name' = 'Widget',
        format('[rest 4/7] name unchanged: got %s', _r);
    ASSERT (_r->>'price')::numeric = 19.99,
        format('[rest 4/7] new price: got %s', _r);
    ASSERT (_r->>'qty')::int = 5,
        format('[rest 4/7] new qty: got %s', _r);
    RAISE NOTICE '[rest 4/7] GET after PUT ok: name=%, price=%, qty=%',
        _r->>'name', _r->>'price', _r->>'qty';

    -- --------------------------------------------------------
    -- 5. DELETE — remove the order
    -- --------------------------------------------------------
    _r := fsql.run('rest.delete',
        format('{"tbl":"fsql._test_orders","id":%s}', _id)::jsonb);
    ASSERT (_r->>'id')::int = _id,
        format('[rest 5/7] DELETE: expected id=%, got %s', _id, _r);
    RAISE NOTICE '[rest 5/7] DELETE ok: %', _r;

    -- --------------------------------------------------------
    -- 6. GET after DELETE — empty result
    -- --------------------------------------------------------
    _r := fsql.run('rest.get',
        format('{"tbl":"fsql._test_orders","id":%s}', _id)::jsonb);
    ASSERT _r = '{}'::jsonb,
        format('[rest 6/7] GET after DELETE: expected {}, got %s', _r);
    RAISE NOTICE '[rest 6/7] GET after DELETE ok: {}';

    -- --------------------------------------------------------
    -- 7. render() on PUT — show SQL without executing
    -- --------------------------------------------------------
    _sql := fsql.render('rest.put',
        '{"tbl":"fsql._test_orders","id":99,"price":29.99,"qty":10}');
    ASSERT _sql LIKE '%UPDATE fsql._test_orders%',
        format('[rest 7/7] render UPDATE: got %s', _sql);
    ASSERT _sql LIKE '%jsonb_populate_record%',
        format('[rest 7/7] render populate: got %s', _sql);
    ASSERT _sql LIKE '%price%' AND _sql LIKE '%qty%',
        format('[rest 7/7] render columns: got %s', _sql);
    RAISE NOTICE '[rest 7/7] render() ok: %', left(_sql, 200);

    RAISE NOTICE '---';
    RAISE NOTICE 'All REST CRUD tests passed';
END;
$test$;

-- ============================================================
-- 4. Cleanup
-- ============================================================
DROP TABLE fsql._test_orders;
DELETE FROM fsql.templates WHERE path LIKE 'rest.%';

\echo ''
\echo 'REST CRUD test complete'
