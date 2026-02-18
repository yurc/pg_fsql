#!/usr/bin/env bash
# Package pg_fsql for distribution
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0"
NAME="pg_fsql-${VERSION}"
OUT="${NAME}.tar.gz"

# Rebuild SQL
bash build_sql.sh

# Create archive with only the files needed for installation
tar czf "$OUT" \
    --transform="s|^|${NAME}/|" \
    src/pg_fsql.c \
    src/render.c \
    sql/parts/*.sql \
    test/run_tests.sh \
    test/sql/*.sql \
    Makefile \
    pg_fsql.control \
    pg_fsql--1.0.sql \
    build_sql.sh \
    README.md

echo "Packaged: $OUT ($(du -h "$OUT" | cut -f1))"
echo ""
echo "Install:"
echo "  tar xzf $OUT"
echo "  cd $NAME"
echo "  make install PG_CONFIG=/usr/bin/pg_config"
echo "  psql -d mydb -c 'CREATE EXTENSION pg_fsql;'"
