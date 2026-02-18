/*
 * execute.c — SPI plan caching for fsql template execution.
 *
 * Provides:
 *   fsql._c_execute(sql text, params text[], use_cache boolean) → jsonb
 *   fsql.clear_cache() → void
 *
 * When use_cache=true AND GUC fsql.cache_plans=true, prepared plans are
 * kept in a backend-local HTAB (TopMemoryContext).  Key = uint64 hash of
 * the SQL text.  SPI_keepplan() makes the plan survive across transactions.
 */
#include "postgres.h"
#include "fmgr.h"
#include "executor/spi.h"
#include "utils/builtins.h"
#include "utils/hsearch.h"
#include "utils/memutils.h"
#include "access/hash.h"
#include "catalog/pg_type.h"

/* GUC defined in pg_fsql.c */
extern bool fsql_cache_plans;

/* ----------------------------------------------------------------
 *  Plan cache — backend-local hash table
 * ---------------------------------------------------------------- */
typedef struct PlanCacheEntry
{
    uint64      key;            /* hash_any_extended(sql) */
    SPIPlanPtr  plan;           /* kept via SPI_keepplan  */
} PlanCacheEntry;

static HTAB *plan_cache = NULL;

static void
ensure_plan_cache(void)
{
    HASHCTL ctl;

    if (plan_cache != NULL)
        return;

    memset(&ctl, 0, sizeof(ctl));
    ctl.keysize   = sizeof(uint64);
    ctl.entrysize = sizeof(PlanCacheEntry);
    ctl.hcxt      = TopMemoryContext;

    plan_cache = hash_create("fsql plan cache",
                             128,           /* initial buckets */
                             &ctl,
                             HASH_ELEM | HASH_BLOBS | HASH_CONTEXT);
}

/* ----------------------------------------------------------------
 *  fsql._c_execute(sql text, params text[], use_cache bool) → jsonb
 * ---------------------------------------------------------------- */
PG_FUNCTION_INFO_V1(fsql_c_execute);

Datum
fsql_c_execute(PG_FUNCTION_ARGS)
{
    text       *sql_text;
    char       *sql;
    bool        use_cache;
    SPIPlanPtr  plan = NULL;
    Datum       values[1];
    char        nulls_arr[1];
    int         ret;
    Datum       result;
    bool        isnull;
    Oid         argtypes[1] = {TEXTARRAYOID};

    /* --- arguments ------------------------------------------------ */
    if (PG_ARGISNULL(0))
        PG_RETURN_NULL();

    sql_text = PG_GETARG_TEXT_PP(0);
    sql      = text_to_cstring(sql_text);

    if (PG_ARGISNULL(1))
    {
        nulls_arr[0] = 'n';
        values[0]    = (Datum) 0;
    }
    else
    {
        nulls_arr[0] = ' ';
        values[0]    = PG_GETARG_DATUM(1);
    }

    use_cache = PG_ARGISNULL(2) ? false : PG_GETARG_BOOL(2);

    /* --- SPI ------------------------------------------------------ */
    if (SPI_connect() != SPI_OK_CONNECT)
        elog(ERROR, "fsql._c_execute: SPI_connect failed");

    if (use_cache && fsql_cache_plans)
    {
        uint64          key;
        bool            found;
        PlanCacheEntry *entry;

        ensure_plan_cache();
        key = hash_any_extended((const unsigned char *) sql,
                                strlen(sql), 0);

        entry = (PlanCacheEntry *)
            hash_search(plan_cache, &key, HASH_FIND, &found);

        if (found)
        {
            plan = entry->plan;
        }
        else
        {
            plan = SPI_prepare(sql, 1, argtypes);
            if (plan == NULL)
                elog(ERROR, "fsql._c_execute: SPI_prepare failed: %s",
                     SPI_result_code_string(SPI_result));

            if (SPI_keepplan(plan) != 0)
                elog(ERROR, "fsql._c_execute: SPI_keepplan failed");

            entry = (PlanCacheEntry *)
                hash_search(plan_cache, &key, HASH_ENTER, &found);
            entry->plan = plan;
        }
    }
    else
    {
        /* one-shot plan — freed automatically by SPI_finish */
        plan = SPI_prepare(sql, 1, argtypes);
        if (plan == NULL)
            elog(ERROR, "fsql._c_execute: SPI_prepare failed: %s",
                 SPI_result_code_string(SPI_result));
    }

    /* --- execute -------------------------------------------------- */
    ret = SPI_execute_plan(plan, values, nulls_arr, false, 1);
    if (ret < 0)
        elog(ERROR, "fsql._c_execute: SPI_execute_plan failed: %s",
             SPI_result_code_string(ret));

    /* --- extract first column of first row ----------------------- */
    if (SPI_processed > 0 && SPI_tuptable != NULL)
    {
        bool attbyval;
        int  attlen;

        result = SPI_getbinval(SPI_tuptable->vals[0],
                               SPI_tuptable->tupdesc,
                               1, &isnull);
        if (isnull)
        {
            SPI_finish();
            pfree(sql);
            PG_RETURN_NULL();
        }

        /* Copy datum out of SPI memory context before SPI_finish */
        attbyval = SPI_tuptable->tupdesc->attrs[0].attbyval;
        attlen   = SPI_tuptable->tupdesc->attrs[0].attlen;
        result   = SPI_datumTransfer(result, attbyval, attlen);
    }
    else
    {
        SPI_finish();
        pfree(sql);
        PG_RETURN_NULL();
    }

    SPI_finish();
    pfree(sql);
    PG_RETURN_DATUM(result);
}

/* ----------------------------------------------------------------
 *  fsql.clear_cache() → void
 *
 *  Frees all cached plans and destroys the hash table.
 *  Call after DDL changes or when you want a fresh start.
 * ---------------------------------------------------------------- */
PG_FUNCTION_INFO_V1(fsql_clear_cache);

Datum
fsql_clear_cache(PG_FUNCTION_ARGS)
{
    if (plan_cache != NULL)
    {
        HASH_SEQ_STATUS  status;
        PlanCacheEntry  *entry;

        hash_seq_init(&status, plan_cache);
        while ((entry = (PlanCacheEntry *) hash_seq_search(&status)) != NULL)
        {
            if (entry->plan != NULL)
                SPI_freeplan(entry->plan);
        }

        hash_destroy(plan_cache);
        plan_cache = NULL;
    }

    PG_RETURN_VOID();
}
