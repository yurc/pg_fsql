-- ============================================================
-- 06-cache.sql  —  SPI Plan Caching tests
-- ============================================================
-- Тестируем: _c_execute, plan cache HTAB, GUC fsql.cache_plans,
-- колонку cached в templates, clear_cache().
--
-- Предпосылки: 00-seed.sql загружен.
-- ============================================================
\set ON_ERROR_STOP on

-- ============================================================
-- 1. Базовая работа: cached=false (default) — поведение не
--    изменилось, планы не кэшируются, результат корректный.
-- ============================================================
DO $test$
DECLARE
    _r jsonb;
BEGIN
    -- demo_count имеет cached=false в seed
    _r := fsql.run('demo_count', '{"src":"pg_class","filter":"true"}');
    ASSERT (_r->>'total')::int > 0,
        format('Uncached exec: expected >0, got %s', _r);

    _r := fsql.run('demo_defaults', '{}');
    ASSERT _r->>'msg' = 'hello world',
        format('Uncached defaults: got %s', _r);

    RAISE NOTICE '[cache 1/7] cached=false baseline OK';
END;
$test$;

-- ============================================================
-- 2. Прямой вызов _c_execute — use_cache=false.
--    Проверяем, что C-функция корректно исполняет SQL через
--    SPI и возвращает jsonb.
-- ============================================================
DO $test$
DECLARE
    _r jsonb;
BEGIN
    _r := fsql._c_execute(
        'SELECT jsonb_build_object(''n'', $1[1]::bigint + $1[2]::bigint)',
        ARRAY['10','32'],
        false);
    ASSERT (_r->>'n')::int = 42,
        format('_c_execute basic: expected 42, got %s', _r);

    -- NULL params → $1 is NULL
    _r := fsql._c_execute(
        'SELECT jsonb_build_object(''v'', coalesce($1[1], ''fallback''))',
        NULL,
        false);
    ASSERT _r->>'v' = 'fallback',
        format('_c_execute NULL params: expected fallback, got %s', _r);

    -- Пустой результат → NULL
    _r := fsql._c_execute(
        'SELECT jsonb_build_object(''x'',1) WHERE false',
        ARRAY[]::text[],
        false);
    ASSERT _r IS NULL,
        format('_c_execute empty result: expected NULL, got %s', _r);

    RAISE NOTICE '[cache 2/7] _c_execute (no cache) OK';
END;
$test$;

-- ============================================================
-- 3. Кэширование планов: cached=true, GUC=on.
--    Два вызова с одинаковым SQL — второй использует кэш.
--    Результат идентичен.
-- ============================================================
DO $test$
DECLARE
    _r1 jsonb;
    _r2 jsonb;
BEGIN
    -- Убедимся что GUC включён
    SET fsql.cache_plans = true;

    UPDATE fsql.templates SET cached = true WHERE path = 'demo_count';

    _r1 := fsql.run('demo_count', '{"src":"pg_class","filter":"true"}');
    _r2 := fsql.run('demo_count', '{"src":"pg_class","filter":"true"}');
    ASSERT _r1 = _r2,
        format('Cache hit: results differ: %s vs %s', _r1, _r2);
    ASSERT (_r1->>'total')::int > 0,
        format('Cache hit: expected >0, got %s', _r1);

    -- Вернём обратно
    UPDATE fsql.templates SET cached = false WHERE path = 'demo_count';

    RAISE NOTICE '[cache 3/7] cache hit (same SQL) OK';
END;
$test$;

-- ============================================================
-- 4. Разные данные → разный SQL → разные кэш-записи.
--    Один шаблон, два набора не-параметризованных данных.
--    Должны быть разные результаты (разные таблицы).
-- ============================================================
DO $test$
DECLARE
    _r1 jsonb;
    _r2 jsonb;
BEGIN
    SET fsql.cache_plans = true;
    UPDATE fsql.templates SET cached = true WHERE path = 'demo_count';

    _r1 := fsql.run('demo_count', '{"src":"pg_class","filter":"true"}');
    _r2 := fsql.run('demo_count', '{"src":"pg_attribute","filter":"true"}');

    ASSERT _r1 IS DISTINCT FROM _r2,
        format('Different SQL: should differ: %s vs %s', _r1, _r2);
    ASSERT (_r1->>'total')::int > 0 AND (_r2->>'total')::int > 0,
        'Different SQL: both should be > 0';
    -- pg_attribute всегда больше pg_class
    ASSERT (_r2->>'total')::int > (_r1->>'total')::int,
        format('Different SQL: pg_attribute (%s) should > pg_class (%s)',
               _r2->>'total', _r1->>'total');

    UPDATE fsql.templates SET cached = false WHERE path = 'demo_count';
    PERFORM fsql.clear_cache();

    RAISE NOTICE '[cache 4/7] different data → different plans OK';
END;
$test$;

-- ============================================================
-- 5. clear_cache() — сброс кэша.
--    После сброса шаблон продолжает работать (новый prepare).
-- ============================================================
DO $test$
DECLARE
    _r jsonb;
BEGIN
    SET fsql.cache_plans = true;
    UPDATE fsql.templates SET cached = true WHERE path = 'demo_count';

    -- Наполняем кэш
    PERFORM fsql.run('demo_count', '{"src":"pg_class","filter":"true"}');

    -- Сбрасываем
    PERFORM fsql.clear_cache();

    -- Должно работать — пересоздаст план
    _r := fsql.run('demo_count', '{"src":"pg_class","filter":"true"}');
    ASSERT (_r->>'total')::int > 0,
        format('After clear_cache: expected >0, got %s', _r);

    -- Двойной сброс — не падает
    PERFORM fsql.clear_cache();
    PERFORM fsql.clear_cache();

    UPDATE fsql.templates SET cached = false WHERE path = 'demo_count';

    RAISE NOTICE '[cache 5/7] clear_cache() OK';
END;
$test$;

-- ============================================================
-- 6. GUC fsql.cache_plans=false — глобальное отключение.
--    Даже при cached=true шаблон выполняется, но без кэша.
-- ============================================================
DO $test$
DECLARE
    _r jsonb;
BEGIN
    UPDATE fsql.templates SET cached = true WHERE path = 'demo_count';

    SET fsql.cache_plans = false;
    _r := fsql.run('demo_count', '{"src":"pg_class","filter":"true"}');
    ASSERT (_r->>'total')::int > 0,
        format('GUC off: expected >0, got %s', _r);

    -- Повторный вызов — тоже ок (каждый раз SPI_prepare)
    _r := fsql.run('demo_count', '{"src":"pg_class","filter":"true"}');
    ASSERT (_r->>'total')::int > 0,
        format('GUC off repeat: expected >0, got %s', _r);

    SET fsql.cache_plans = true;
    UPDATE fsql.templates SET cached = false WHERE path = 'demo_count';

    RAISE NOTICE '[cache 6/7] GUC off → no cache, still works OK';
END;
$test$;

-- ============================================================
-- 7. Полный цикл через run() с exec_tpl и ref.
--    Проверяем, что cached не ломает другие cmd-типы.
-- ============================================================
DO $test$
DECLARE
    _r jsonb;
BEGIN
    SET fsql.cache_plans = true;

    -- ref → demo_count: ref не exec, cached не влияет
    _r := fsql.run('demo_ref', '{"src":"pg_class","filter":"true"}');
    ASSERT (_r->>'total')::int > 0,
        format('ref through cache: expected >0, got %s', _r);

    -- if → не exec, cached не влияет
    _r := fsql.run('demo_if', '{"mode":"fast"}');
    ASSERT _r->>'key' = 'index scan',
        format('if through cache: expected index scan, got %s', _r);

    -- defaults
    _r := fsql.run('demo_defaults', '{"target":"cache_test"}');
    ASSERT _r->>'msg' = 'hello cache_test',
        format('defaults through cache: got %s', _r);

    PERFORM fsql.clear_cache();

    RAISE NOTICE '[cache 7/7] non-exec cmd types unaffected OK';
END;
$test$;

\echo ''
\echo 'All plan cache tests passed'
