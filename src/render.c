/*
 * render.c — C implementation of {d[key]} / {d[key]!r} substitution.
 *
 * Replaces data_algorithms.f_template_load_sql with a single-function
 * C implementation for better performance on hot paths.
 *
 * Patterns:
 *   {d[key]}   — plain substitution (NULL → "null")
 *   {d[key]!r} — quote_literal substitution (NULL → '')
 *   {d[key]!j} — jsonb literal: '<json_value>'::jsonb
 *   {d[key]!i} — quote_identifier substitution (reserved words → "word")
 *
 * Sorting: values that themselves contain "{d[" are substituted first,
 * so nested patterns from substituted values can be resolved.
 */
#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/jsonb.h"
#include "utils/numeric.h"
#include "lib/stringinfo.h"

/* ----------------------------------------------------------------
 * Helper: quote a C string as a SQL literal
 * Surrounds with single quotes, doubles internal single quotes.
 * ---------------------------------------------------------------- */
static char *
quote_literal_cstr_impl(const char *str)
{
    StringInfoData buf;
    const char    *p;

    initStringInfo(&buf);
    appendStringInfoChar(&buf, '\'');
    for (p = str; *p != '\0'; p++)
    {
        if (*p == '\'')
            appendStringInfoString(&buf, "''");
        else
            appendStringInfoChar(&buf, *p);
    }
    appendStringInfoChar(&buf, '\'');
    return buf.data;
}

/* ----------------------------------------------------------------
 * Helper: JSON-escape a string and wrap in double quotes.
 * hello → "hello",  O'Brien → "O'Brien",  a"b → "a\"b"
 * ---------------------------------------------------------------- */
static char *
json_escape_string(const char *str)
{
    StringInfoData buf;
    const char    *p;

    initStringInfo(&buf);
    appendStringInfoChar(&buf, '"');
    for (p = str; *p != '\0'; p++)
    {
        switch (*p)
        {
            case '"':  appendStringInfoString(&buf, "\\\""); break;
            case '\\': appendStringInfoString(&buf, "\\\\"); break;
            case '\n': appendStringInfoString(&buf, "\\n"); break;
            case '\r': appendStringInfoString(&buf, "\\r"); break;
            case '\t': appendStringInfoString(&buf, "\\t"); break;
            default:
                if ((unsigned char)*p < 0x20)
                    appendStringInfo(&buf, "\\u%04x", (unsigned char)*p);
                else
                    appendStringInfoChar(&buf, *p);
                break;
        }
    }
    appendStringInfoChar(&buf, '"');
    return buf.data;
}

/* ----------------------------------------------------------------
 * Helper: replace all occurrences of `find` in `str` with `repl`.
 * Returns a palloc'd string.
 * ---------------------------------------------------------------- */
static char *
str_replace_all(const char *str, const char *find, const char *repl)
{
    StringInfoData buf;
    const char    *p, *q;
    int            find_len;

    find_len = strlen(find);
    if (find_len == 0)
        return pstrdup(str);

    initStringInfo(&buf);
    p = str;
    while ((q = strstr(p, find)) != NULL)
    {
        appendBinaryStringInfo(&buf, p, (int)(q - p));
        appendStringInfoString(&buf, repl);
        p = q + find_len;
    }
    appendStringInfoString(&buf, p);
    return buf.data;
}

/* ----------------------------------------------------------------
 * Key-value pair extracted from the JSONB argument.
 * ---------------------------------------------------------------- */
typedef struct
{
    char   *key;
    char   *value;          /* NULL when jsonb value is null */
    bool    is_null;
    bool    value_has_pattern;
    int     orig_type;      /* jbvString, jbvNumeric, jbvBool, jbvNull, jbvBinary */
} RenderKV;

/* ----------------------------------------------------------------
 * fsql._c_render(template text, data jsonb) RETURNS text
 * ---------------------------------------------------------------- */
PG_FUNCTION_INFO_V1(fsql_c_render);

Datum
fsql_c_render(PG_FUNCTION_ARGS)
{
    text           *tmpl_text;
    Jsonb          *data;
    char           *result;
    JsonbIterator  *it;
    JsonbValue      v;
    JsonbIteratorToken tok;

    RenderKV       *pairs = NULL;
    int             npairs = 0;
    int             cap = 0;
    int             i, j;

    /* NULL template → NULL */
    if (PG_ARGISNULL(0))
        PG_RETURN_NULL();

    tmpl_text = PG_GETARG_TEXT_PP(0);
    result = text_to_cstring(tmpl_text);

    /* NULL data → return template unchanged */
    if (PG_ARGISNULL(1))
        PG_RETURN_TEXT_P(cstring_to_text(result));

    data = PG_GETARG_JSONB_P(1);

    /* Only process JSON objects */
    if (!JB_ROOT_IS_OBJECT(data) || JB_ROOT_COUNT(data) == 0)
        PG_RETURN_TEXT_P(cstring_to_text(result));

    /* ----- Extract key/value pairs from JSONB ----- */
    it = JsonbIteratorInit(&data->root);
    while ((tok = JsonbIteratorNext(&it, &v, false)) != WJB_DONE)
    {
        if (tok == WJB_KEY)
        {
            char       *key;
            char       *val = NULL;
            bool        is_null = false;
            int         jtype = jbvNull;
            JsonbValue  val_v;

            key = pnstrdup(v.val.string.val, v.val.string.len);

            /* skipNested=true: arrays/objects returned as single jbvBinary */
            tok = JsonbIteratorNext(&it, &val_v, true);
            if (tok == WJB_VALUE)
            {
                jtype = val_v.type;
                switch (val_v.type)
                {
                    case jbvString:
                        val = pnstrdup(val_v.val.string.val, val_v.val.string.len);
                        break;
                    case jbvNumeric:
                        val = DatumGetCString(
                            DirectFunctionCall1(numeric_out,
                                NumericGetDatum(val_v.val.numeric)));
                        break;
                    case jbvBool:
                        val = pstrdup(val_v.val.boolean ? "true" : "false");
                        break;
                    case jbvNull:
                        is_null = true;
                        break;
                    default:
                        {
                            /* Nested object / array → serialize to text */
                            Jsonb *nested = JsonbValueToJsonb(&val_v);
                            val = JsonbToCString(NULL, &nested->root,
                                                 VARSIZE(nested));
                        }
                        break;
                }
            }
            else
            {
                is_null = true;
            }

            /* Grow array if needed */
            if (npairs >= cap)
            {
                cap = cap ? cap * 2 : 16;
                if (pairs == NULL)
                    pairs = palloc(sizeof(RenderKV) * cap);
                else
                    pairs = repalloc(pairs, sizeof(RenderKV) * cap);
            }
            pairs[npairs].key   = key;
            pairs[npairs].value = val;
            pairs[npairs].is_null = is_null;
            pairs[npairs].value_has_pattern =
                (val != NULL && strstr(val, "{d[") != NULL);
            pairs[npairs].orig_type = jtype;
            npairs++;
        }
    }

    /* ----- Virtual _self: full input JSON, no duplication ----- */
    if (strstr(result, "{d[_self]") != NULL)
    {
        bool has_self = false;
        for (i = 0; i < npairs; i++)
        {
            if (strcmp(pairs[i].key, "_self") == 0)
            {
                has_self = true;
                break;
            }
        }
        if (!has_self)
        {
            char *full_json = JsonbToCString(NULL, &data->root,
                                             VARSIZE(data));
            if (npairs >= cap)
            {
                cap = cap ? cap * 2 : 16;
                pairs = repalloc(pairs, sizeof(RenderKV) * cap);
            }
            pairs[npairs].key   = pstrdup("_self");
            pairs[npairs].value = full_json;
            pairs[npairs].is_null = false;
            pairs[npairs].value_has_pattern = false;
            pairs[npairs].orig_type = jbvBinary;
            npairs++;
        }
    }

    /* ----- Sort: values containing {d[ come first ----- */
    for (i = 0; i < npairs - 1; i++)
    {
        for (j = i + 1; j < npairs; j++)
        {
            if (!pairs[i].value_has_pattern && pairs[j].value_has_pattern)
            {
                RenderKV tmp = pairs[i];
                pairs[i] = pairs[j];
                pairs[j] = tmp;
            }
        }
    }

    /* ----- Perform replacements ----- */
    for (i = 0; i < npairs; i++)
    {
        int   key_len = strlen(pairs[i].key);
        char *pat_r;    /* {d[key]!r} */
        char *pat_j;    /* {d[key]!j} */
        char *pat_i;    /* {d[key]!i} */
        char *pat;      /* {d[key]}   */

        pat_r = palloc(key_len + 8);   /* {d[...]!r}\0  = 3+key+4+1 */
        sprintf(pat_r, "{d[%s]!r}", pairs[i].key);

        pat_j = palloc(key_len + 8);   /* {d[...]!j}\0  = 3+key+4+1 */
        sprintf(pat_j, "{d[%s]!j}", pairs[i].key);

        pat_i = palloc(key_len + 8);   /* {d[...]!i}\0  = 3+key+4+1 */
        sprintf(pat_i, "{d[%s]!i}", pairs[i].key);

        pat = palloc(key_len + 6);     /* {d[...]}\0   = 3+key+2+1 */
        sprintf(pat, "{d[%s]}", pairs[i].key);

        /* !r pattern → quote_literal */
        if (strstr(result, pat_r))
        {
            const char *raw = pairs[i].is_null ? "" : pairs[i].value;
            char *quoted = quote_literal_cstr_impl(raw);
            char *new_result = str_replace_all(result, pat_r, quoted);
            pfree(result);
            pfree(quoted);
            result = new_result;
        }

        /* !j pattern → '<json_value>'::jsonb */
        if (strstr(result, pat_j))
        {
            char *json_val;
            char *quoted;
            char *with_cast;
            char *new_result;

            if (pairs[i].is_null)
            {
                json_val = pstrdup("null");
            }
            else if (pairs[i].orig_type == jbvString)
            {
                /* bare string → JSON-encode: hello → "hello" */
                json_val = json_escape_string(pairs[i].value);
            }
            else
            {
                /* numeric, bool, array, object — already valid JSON */
                json_val = pstrdup(pairs[i].value);
            }

            quoted = quote_literal_cstr_impl(json_val);
            with_cast = palloc(strlen(quoted) + 8);
            sprintf(with_cast, "%s::jsonb", quoted);

            new_result = str_replace_all(result, pat_j, with_cast);
            pfree(result);
            pfree(json_val);
            pfree(quoted);
            pfree(with_cast);
            result = new_result;
        }

        /* !i pattern → quote_identifier */
        if (strstr(result, pat_i))
        {
            const char *raw = pairs[i].is_null ? "" : pairs[i].value;
            const char *quoted = quote_identifier(raw);
            char *new_result = str_replace_all(result, pat_i, quoted);
            pfree(result);
            result = new_result;
        }

        /* Plain pattern */
        if (strstr(result, pat))
        {
            const char *repl = pairs[i].is_null ? "null" : pairs[i].value;
            char *new_result = str_replace_all(result, pat, repl);
            pfree(result);
            result = new_result;
        }

        pfree(pat_r);
        pfree(pat_j);
        pfree(pat_i);
        pfree(pat);
    }

    if (pairs)
        pfree(pairs);

    PG_RETURN_TEXT_P(cstring_to_text(result));
}
