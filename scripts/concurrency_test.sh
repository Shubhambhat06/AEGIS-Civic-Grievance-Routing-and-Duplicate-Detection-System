#!/usr/bin/env bash
# =====================================================================
# Concurrency demonstration (syllabus Unit 4: transactions, concurrency
# control, locking).
#
# Two staff members review the same complaint at the same moment and
# both click "merge into #15". Without locking this is a lost-update
# race: both could insert a duplicate_link row and both could increment
# complaint.duplicate_count, leaving the counter at 2 for one real
# duplicate.
#
# fn_merge_duplicate takes SELECT ... FOR UPDATE row locks on both
# complaints before doing anything. This script proves the race is
# actually prevented:
#
#   Session A  BEGIN -> merge -> hold the transaction open -> COMMIT
#   Session B      BEGIN -> merge (blocks on A's lock) -> fails -> ROLLBACK
#
# Expected result: exactly one duplicate_link row, counter exactly 1.
#
# Usage: bash scripts/concurrency_test.sh
# =====================================================================
set -uo pipefail

PSQL="psql -h ${PGHOST:-/tmp} -p ${PGPORT:-5433} -U ${PGUSER:-postgres} -d ${PGDATABASE:-aegis_test} -X -q -A -t"
OUT=$(mktemp -d)

echo "=== Concurrency test: two staff merging the same complaint ==="
echo

# Pick a child complaint that has not been merged yet.
CHILD=$($PSQL -c "SELECT c.complaint_id FROM complaint c
                   WHERE c.status NOT IN ('MERGED','RESOLVED')
                     AND NOT EXISTS (SELECT 1 FROM duplicate_link d
                                      WHERE d.child_complaint_id = c.complaint_id)
                     AND c.complaint_id <> 15
                   ORDER BY c.complaint_id LIMIT 1;")
PARENT=15

echo "child=#$CHILD  parent=#$PARENT"
BEFORE=$($PSQL -c "SELECT duplicate_count FROM complaint WHERE complaint_id=$PARENT;")
echo "parent duplicate_count before: $BEFORE"
echo

# ---- Session A: merge, then hold the transaction open for 3 seconds --
(
  $PSQL > "$OUT/a.log" 2>&1 <<SQL
BEGIN;
SELECT 'A: acquiring locks and merging';
SELECT fn_merge_duplicate($CHILD, $PARENT, 0.91, 2);
SELECT 'A: merged, holding transaction open';
SELECT pg_sleep(3);
COMMIT;
SELECT 'A: committed';
SQL
) &
A_PID=$!

# ---- Session B: start shortly after, attempt the identical merge -----
sleep 1
(
  $PSQL > "$OUT/b.log" 2>&1 <<SQL
BEGIN;
SELECT 'B: attempting the same merge';
SELECT fn_merge_duplicate($CHILD, $PARENT, 0.91, 3);
SELECT 'B: UNEXPECTED SUCCESS';
COMMIT;
SQL
) &
B_PID=$!

wait $A_PID $B_PID 2>/dev/null

echo "--- Session A ---"
sed 's/^/    /' "$OUT/a.log"
echo "--- Session B ---"
sed 's/^/    /' "$OUT/b.log"
echo

AFTER=$($PSQL -c "SELECT duplicate_count FROM complaint WHERE complaint_id=$PARENT;")
LINKS=$($PSQL -c "SELECT count(*) FROM duplicate_link WHERE child_complaint_id=$CHILD;")
STATUS=$($PSQL -c "SELECT status FROM complaint WHERE complaint_id=$CHILD;")

echo "=== Result ==="
echo "  duplicate_link rows for #$CHILD : $LINKS   (expected 1)"
echo "  parent duplicate_count          : $BEFORE -> $AFTER   (expected +1)"
echo "  child status                    : $STATUS   (expected MERGED)"
echo

FAIL=0
[ "$LINKS" = "1" ] || { echo "FAIL: expected exactly one link row"; FAIL=1; }
[ "$AFTER" = "$((BEFORE + 1))" ] || { echo "FAIL: counter incremented more than once"; FAIL=1; }
[ "$STATUS" = "MERGED" ] || { echo "FAIL: child not marked MERGED"; FAIL=1; }
grep -q "UNEXPECTED SUCCESS" "$OUT/b.log" && { echo "FAIL: both sessions merged"; FAIL=1; }

rm -rf "$OUT"
if [ $FAIL -eq 0 ]; then
    echo "PASS - the race was prevented; exactly one merge took effect."
else
    echo "CONCURRENCY TEST FAILED"
fi
exit $FAIL
