#!/usr/bin/env bash
# Run all pg_fsql tests inside the PostgreSQL container
set -euo pipefail

DB="${PGDATABASE:-test_db}"
USER="${PGUSER:-postgres}"
HOST="${PGHOST:-localhost}"
TESTS_DIR="$(dirname "$0")/sql"
FAILED=0
PASSED=0

echo "=== pg_fsql test suite ==="
echo "Database: $DB  User: $USER"
echo ""

for f in "$TESTS_DIR"/*.sql; do
    name=$(basename "$f")
    printf "%-40s " "$name"
    if output=$(psql -U "$USER" -d "$DB" -v ON_ERROR_STOP=1 -f "$f" 2>&1); then
        echo "PASS"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL"
        echo "$output" | tail -10
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "Results: $PASSED passed, $FAILED failed"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
echo "All tests passed!"
