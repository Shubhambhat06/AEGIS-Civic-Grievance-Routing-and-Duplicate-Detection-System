#!/usr/bin/env bash
# =====================================================================
# Executes the AEGIS SQL files against a throwaway database and reports
# any error. Used to verify the scripts actually run before submission.
#
# Usage:  bash scripts/run_tests.sh
#
# If pgvector is not installed on this machine the script falls back to
# a REAL[] shim so everything except the HNSW index can still be tested.
# =====================================================================
set -uo pipefail

PSQL="psql -h ${PGHOST:-/tmp} -p ${PGPORT:-5433} -U ${PGUSER:-postgres} -v ON_ERROR_STOP=1 -X -q"
DB=aegis_test
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d)

echo "== dropping and recreating $DB"
$PSQL -d postgres -c "DROP DATABASE IF EXISTS $DB;"   >/dev/null
$PSQL -d postgres -c "CREATE DATABASE $DB;"           >/dev/null

# Does this server have pgvector?
if $PSQL -d $DB -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null 2>&1; then
    HAVE_PGVECTOR=1
    echo "== pgvector: available (testing the real schema unmodified)"
    cp "$ROOT"/db/0*.sql "$WORK"/
else
    HAVE_PGVECTOR=0
    echo "== pgvector: NOT available (using REAL[] shim; HNSW index skipped)"
    $PSQL -d $DB -f "$ROOT/db/_test_stub_pgvector.sql" >/dev/null
    for f in "$ROOT"/db/0*.sql; do
        sed -e 's/CREATE EXTENSION IF NOT EXISTS vector;//' \
            -e 's/VECTOR(384)/REAL[]/g' \
            -e '/USING hnsw/s/^/-- SHIM-SKIPPED /' \
            -e '/idx_embedding_hnsw/s/^/-- SHIM-SKIPPED /' \
            "$f" > "$WORK/$(basename "$f")"
    done
fi

FAIL=0
for f in "$WORK"/0*.sql; do
    name=$(basename "$f")
    out=$($PSQL -d $DB -f "$f" 2>&1)
    if [ $? -ne 0 ]; then
        echo "FAIL  $name"
        echo "$out" | grep -E '^psql:|ERROR' | head -15
        FAIL=1
    else
        echo "ok    $name"
        echo "$out" | grep -E 'NOTICE|WARNING' | head -60
    fi
done

rm -rf "$WORK"
echo
if [ $FAIL -eq 0 ]; then
    echo "ALL SQL FILES EXECUTED SUCCESSFULLY"
else
    echo "SOME FILES FAILED"
fi
exit $FAIL
