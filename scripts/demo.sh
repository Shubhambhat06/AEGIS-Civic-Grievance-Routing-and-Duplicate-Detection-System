#!/usr/bin/env bash
# =====================================================================
# AEGIS - guided demonstration.
#
# Walks through the five things the project is meant to show, printing
# the actual database output at each step. Use this to drive the live
# demo, or read it as a script for what to say.
#
# Local:   PGHOST=/tmp PGPORT=5433 PGDATABASE=aegis_test bash scripts/demo.sh
# Docker (any host shell, including PowerShell):
#          docker compose exec -e PGHOST=/var/run/postgresql db \
#              bash /aegis-scripts/demo.sh
#
# Local:   PGHOST=/tmp PGPORT=5433 PGDATABASE=aegis_test bash scripts/demo.sh
# Docker:  bash scripts/demo.sh            (after docker compose up)
# =====================================================================
set -uo pipefail

# Docker Compose publishes PostgreSQL on localhost:5432 with user aegis.
PSQL="psql -h ${PGHOST:-localhost} -p ${PGPORT:-5432} -U ${PGUSER:-aegis} -d ${PGDATABASE:-aegis} -X"

step() {
  echo
  echo "====================================================================="
  echo " $1"
  echo "====================================================================="
}

pause() { [ "${NOPAUSE:-0}" = "1" ] || { echo; read -rp "   [Enter] to continue "; }; }

$PSQL -tAc "SELECT 1" >/dev/null 2>&1 || {
  echo "Cannot reach the database."
  echo "  Docker: docker compose up -d, then re-run."
  echo "  Local:  PGHOST=/tmp PGPORT=5433 PGUSER=postgres PGDATABASE=aegis_test bash scripts/demo.sh"
  exit 1
}

step "1. THE PROBLEM - four people reported the same pothole"
echo
echo "Four citizens in the same ward described one pothole in four"
echo "different ways. Notice how few words they share."
echo
$PSQL -c "
SELECT c.complaint_id AS id, ct.full_name AS reported_by, c.title
FROM complaint c JOIN citizen ct ON ct.citizen_id = c.citizen_id
WHERE c.complaint_id BETWEEN 15 AND 18
ORDER BY c.complaint_id;"
echo "A keyword search cannot connect 'pothole' to 'crater'. This is why"
echo "the description is stored as a vector, not just as text."
pause

step "2. VECTOR SIMILARITY SEARCH finds them anyway"
echo
echo "fn_find_duplicates embeds the description into 384 dimensions and"
echo "ranks earlier complaints in the SAME WARD by cosine similarity."
echo
$PSQL -c "SELECT * FROM fn_find_duplicates(18, 0.30, 5);"
echo "The two strongest matches are pothole reports - the live one (#15)"
echo "and the historical resolved one (#1) - even though #18 says"
echo "'road damage' and shares almost no words with either."
echo
echo "The weaker match further down is why the production threshold is"
echo "0.80, not 0.30: this listing was deliberately widened so the"
echo "ranking is visible. Staff review the candidates before merging."
pause

step "3. AUTOMATIC ROUTING learned from resolution history"
echo
echo "No citizen picked a department from a dropdown. Each complaint was"
echo "routed by a similarity-weighted vote over the departments that"
echo "resolved the most similar past complaints."
echo
$PSQL -c "
SELECT c.complaint_id AS id, left(c.title, 38) AS title, d.dept_name AS routed_to
FROM complaint c JOIN department d ON d.dept_id = c.dept_id
WHERE c.complaint_id BETWEEN 19 AND 24
ORDER BY c.complaint_id;"
pause

step "4. THE MERGE is one transaction"
echo
echo "Three duplicates were merged into #15. fn_merge_duplicate writes"
echo "the link, marks the child MERGED and increments the parent counter"
echo "atomically - all three, or none."
echo
$PSQL -c "
SELECT dl.child_complaint_id AS duplicate, dl.parent_complaint_id AS merged_into,
       round(dl.similarity_score::numeric, 2) AS similarity, s.full_name AS approved_by
FROM duplicate_link dl LEFT JOIN staff s ON s.staff_id = dl.merged_by
ORDER BY dl.child_complaint_id;"
$PSQL -c "
SELECT complaint_id AS id, left(title,36) AS title, status, duplicate_count AS extra_reports
FROM complaint WHERE complaint_id = 15;"
echo "The citizens who filed the duplicates have not lost anything - their"
echo "complaint still tracks the parent issue:"
echo
$PSQL -c "
SELECT complaint_id AS id, status, parent_complaint_id AS now_tracking, merged_into_status
FROM v_citizen_complaints WHERE parent_complaint_id IS NOT NULL ORDER BY complaint_id;"
pause

step "5. SLA ESCALATION runs on a schedule"
echo
# If the test suite has already run against this database, the overdue
# complaints are ESCALATED and the sweep would have nothing to do. Put
# them back so the sweep is actually demonstrable.
RESET=$($PSQL -tAc "
WITH reset AS (
  UPDATE complaint SET status='ROUTED'
   WHERE status='ESCALATED' AND sla_deadline < now()
  RETURNING 1
) SELECT count(*) FROM reset;" 2>/dev/null | tr -d ' ')
[ "$RESET" -gt 0 ] && echo "(demo reset: $RESET already-escalated complaint(s) put back to ROUTED)" && echo

echo "Two seeded complaints are already past their deadline:"
echo
$PSQL -c "
SELECT complaint_id AS id, left(title,36) AS title, status,
       round(extract(epoch FROM (now() - sla_deadline))/3600.0, 1) AS hours_overdue
FROM complaint
WHERE sla_deadline < now() AND status NOT IN ('RESOLVED','MERGED')
ORDER BY sla_deadline;"
echo "Running the sweep:"
$PSQL -c "SELECT fn_escalate_overdue() AS complaints_escalated;"
echo "Running it a second time escalates nothing - it is idempotent:"
$PSQL -c "SELECT fn_escalate_overdue() AS complaints_escalated;"
pause

step "6. THE DATABASE REFUSES BAD DATA"
echo
echo "These rules hold no matter which client writes - the web app, a"
echo "stored function, or a manual psql session like this one."
echo
echo "-- merging a complaint into itself:"
$PSQL -c "SELECT fn_merge_duplicate(19, 19, 0.9, 2);" 2>&1 | grep -E "ERROR" | head -1
echo
echo "-- reopening a complaint that is already resolved:"
$PSQL -c "UPDATE complaint SET status='OPEN' WHERE complaint_id=1;" 2>&1 | grep -E "ERROR" | head -1
echo
echo "-- a feedback rating outside 1..5:"
$PSQL -c "INSERT INTO feedback (complaint_id, rating) VALUES (3, 9);" 2>&1 | grep -E "ERROR" | head -1
pause

step "7. THE AUDIT TRAIL is written by a trigger"
echo
$PSQL -c "
SELECT sh.changed_at, COALESCE(sh.old_status::text,'(new)') AS from_status,
       sh.new_status AS to_status, COALESCE(s.full_name,'system') AS by_whom
FROM status_history sh LEFT JOIN staff s ON s.staff_id = sh.changed_by
WHERE sh.complaint_id = 16 ORDER BY sh.changed_at;"
echo "Nothing in the application code wrote those rows."

echo
echo "====================================================================="
echo " End of demonstration."
echo "====================================================================="
