/*
 * pg_fsql.c — Module entry point, _PG_init, GUC
 */
#include "postgres.h"
#include "fmgr.h"
#include "utils/guc.h"

PG_MODULE_MAGIC;

/* GUC: maximum recursion depth */
int fsql_max_depth = 64;

/* GUC: enable SPI plan caching */
bool fsql_cache_plans = true;

void _PG_init(void);

void
_PG_init(void)
{
    DefineCustomIntVariable(
        "fsql.max_depth",
        "Maximum recursion depth for template processing.",
        NULL,
        &fsql_max_depth,
        64,     /* default */
        1,      /* min */
        10000,  /* max */
        PGC_USERSET,
        0,
        NULL, NULL, NULL
    );

    DefineCustomBoolVariable(
        "fsql.cache_plans",
        "Enable SPI plan caching for templates with cached=true.",
        NULL,
        &fsql_cache_plans,
        true,   /* default */
        PGC_USERSET,
        0,
        NULL, NULL, NULL
    );
}
