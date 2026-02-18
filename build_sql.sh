#!/usr/bin/env bash
# Assemble pg_fsql--1.0.sql from sql/parts/*.sql
set -euo pipefail
cd "$(dirname "$0")"

OUT="pg_fsql--1.0.sql"
echo "-- pg_fsql extension SQL (auto-generated, do not edit)" > "$OUT"
echo "-- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$OUT"
echo "" >> "$OUT"

for f in sql/parts/*.sql; do
    echo "-- >>>>>> $f" >> "$OUT"
    cat "$f" >> "$OUT"
    echo "" >> "$OUT"
done

echo "Assembled $OUT from $(ls sql/parts/*.sql | wc -l) parts."
