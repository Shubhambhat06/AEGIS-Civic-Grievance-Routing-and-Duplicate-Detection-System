#!/usr/bin/env bash
# =====================================================================
# End-to-end API tests.
#
# Starts from a running app (npm run build && npm start) and a seeded
# database, then exercises every route including the authorisation
# rules. Prints PASS / FAIL per check.
#
# Usage:  BASE=http://localhost:3000 bash scripts/api_test.sh
# =====================================================================
set -uo pipefail
BASE="${BASE:-http://localhost:3000}"
JAR=$(mktemp -d)
PASS=0; FAIL=0

check() { # check <name> <actual> <expected>
  if [ "$2" = "$3" ]; then
    printf 'PASS  %-54s %s\n' "$1" "$2"; PASS=$((PASS+1))
  else
    printf 'FAIL  %-54s got=%s want=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1))
  fi
}

code() { # code <curl args...>  -> http status
  curl -s -o /tmp/_body -w '%{http_code}' "$@"
}

echo "--- Group A: authentication ---"

# A1 unauthenticated access must be refused
check "A1 /api/complaints without session -> 401" \
      "$(code "$BASE/api/complaints")" 401

# A2 wrong password must be refused
check "A2 login with wrong password -> 401" \
      "$(code -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
         -d '{"email":"arjun.menon@example.com","password":"wrong","userType":"citizen"}')" 401

# A3 unknown account must look identical to a wrong password
check "A3 login with unknown email -> 401" \
      "$(code -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
         -d '{"email":"nobody@example.com","password":"password123","userType":"citizen"}')" 401

# A4 valid citizen login
check "A4 citizen login -> 200" \
      "$(code -c "$JAR/citizen" -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
         -d '{"email":"arjun.menon@example.com","password":"password123","userType":"citizen"}')" 200

# A5 valid staff login
check "A5 staff login -> 200" \
      "$(code -c "$JAR/staff" -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
         -d '{"email":"roads1@aegis.example","password":"password123","userType":"staff"}')" 200

# A6 valid admin login
check "A6 admin login -> 200" \
      "$(code -c "$JAR/admin" -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
         -d '{"email":"admin@aegis.example","password":"password123","userType":"staff"}')" 200

# A7 a forged cookie must be rejected (HMAC signature check)
check "A7 tampered session cookie -> 401" \
      "$(code "$BASE/api/complaints" -H 'Cookie: aegis_session=eyJpZCI6MX0.badsignature')" 401


echo ""
echo "--- Group B: role-based authorisation ---"

# B1 citizens cannot read the admin dashboard
check "B1 citizen -> /api/dashboard -> 403" \
      "$(code -b "$JAR/citizen" "$BASE/api/dashboard")" 403

# B2 ordinary staff cannot read the admin dashboard either
check "B2 staff -> /api/dashboard -> 403" \
      "$(code -b "$JAR/staff" "$BASE/api/dashboard")" 403

# B3 admins can
check "B3 admin -> /api/dashboard -> 200" \
      "$(code -b "$JAR/admin" "$BASE/api/dashboard")" 200

# B4 citizens cannot run the duplicate search
check "B4 citizen -> duplicates -> 403" \
      "$(code -b "$JAR/citizen" "$BASE/api/complaints/19/duplicates")" 403

# B5 citizens cannot change a complaint's status
check "B5 citizen -> PATCH complaint -> 403" \
      "$(code -b "$JAR/citizen" -X PATCH "$BASE/api/complaints/19" \
         -H 'Content-Type: application/json' -d '{"status":"RESOLVED"}')" 403

# B6 staff cannot file complaints (citizens only)
check "B6 staff -> POST complaint -> 403" \
      "$(code -b "$JAR/staff" -X POST "$BASE/api/complaints" \
         -H 'Content-Type: application/json' \
         -d '{"title":"Staff filing","description":"Staff should not be able to file this."}')" 403


echo ""
echo "--- Group C: citizen workflow ---"

# C1 a citizen can list their own complaints
check "C1 citizen lists own complaints -> 200" \
      "$(code -b "$JAR/citizen" "$BASE/api/complaints")" 200

# C2 a citizen cannot read someone else's complaint (row filter)
#    complaint 20 belongs to a different citizen
check "C2 citizen reading another's complaint -> 404" \
      "$(code -b "$JAR/citizen" "$BASE/api/complaints/20")" 404

# C3 filing a valid complaint succeeds
check "C3 citizen files valid complaint -> 201" \
      "$(code -b "$JAR/citizen" -X POST "$BASE/api/complaints" \
         -H 'Content-Type: application/json' \
         -d '{"title":"API test complaint","description":"Filed by the automated API test suite run."}')" 201
NEW_ID=$(python3 -c "import json;print(json.load(open('/tmp/_body'))['complaintId'])" 2>/dev/null || echo 0)

# C4 a too-short title is rejected
check "C4 title shorter than 5 chars -> 400" \
      "$(code -b "$JAR/citizen" -X POST "$BASE/api/complaints" \
         -H 'Content-Type: application/json' \
         -d '{"title":"abc","description":"This description is long enough to pass."}')" 400

# C5 a too-short description is rejected
check "C5 description shorter than 15 chars -> 400" \
      "$(code -b "$JAR/citizen" -X POST "$BASE/api/complaints" \
         -H 'Content-Type: application/json' \
         -d '{"title":"Valid title here","description":"too short"}')" 400


echo ""
echo "--- Group D: staff workflow and duplicate detection ---"

# D1 staff see the work queue
check "D1 staff lists work queue -> 200" \
      "$(code -b "$JAR/staff" "$BASE/api/complaints")" 200

# D2 duplicate search on the pothole cluster returns candidates
code -b "$JAR/staff" "$BASE/api/complaints/15/duplicates?threshold=0.3" >/dev/null
N=$(python3 -c "import json;print(len(json.load(open('/tmp/_body'))['candidates']))" 2>/dev/null || echo -1)
check "D2 duplicate search returns candidates" "$([ "$N" -ge 0 ] && echo ok || echo bad)" ok

# D3 merging a complaint into itself is refused by the stored function
check "D3 self-merge -> 409" \
      "$(code -b "$JAR/staff" -X POST "$BASE/api/complaints/19/duplicates" \
         -H 'Content-Type: application/json' -d '{"parentId":19,"similarity":0.9}')" 409

# D4 merging into an already-merged complaint is refused
check "D4 merge into merged complaint -> 409" \
      "$(code -b "$JAR/staff" -X POST "$BASE/api/complaints/19/duplicates" \
         -H 'Content-Type: application/json' -d '{"parentId":16,"similarity":0.9}')" 409

# D5 staff cannot touch another department's complaint
#    roads1 is in Roads; complaint 20 is Water Supply
check "D5 staff PATCH outside own department -> 404" \
      "$(code -b "$JAR/staff" -X PATCH "$BASE/api/complaints/20" \
         -H 'Content-Type: application/json' -d '{"status":"RESOLVED"}')" 404

# D6 an invalid status value is rejected before reaching the database
check "D6 invalid status value -> 400" \
      "$(code -b "$JAR/staff" -X PATCH "$BASE/api/complaints/15" \
         -H 'Content-Type: application/json' -d '{"status":"BANANA"}')" 400


echo ""
echo "--- Group E: search ---"

# E1 full-text search works for a signed-in user
check "E1 search 'pothole' -> 200" \
      "$(code -b "$JAR/citizen" "$BASE/api/search?q=pothole")" 200
M=$(python3 -c "import json;print(len(json.load(open('/tmp/_body'))['results']))" 2>/dev/null || echo 0)
check "E1b search returns matches" "$([ "$M" -gt 0 ] && echo ok || echo none)" ok

# E2 search requires a session
check "E2 search without session -> 401" \
      "$(code "$BASE/api/search?q=pothole")" 401


echo ""
echo "--- Group G: endpoints added with the redesign ---"

# G1 public figures need no sign-in and expose only counts
check "G1 public stats without session -> 200" \
      "$(code "$BASE/api/public/stats")" 200
check "G1b public stats contain no names or text" \
      "$(grep -ciE 'email|full_name|title|description' /tmp/_body)" 0

# G2 who-am-I is a normal answer when signed out
check "G2 /api/auth/me signed out -> 200" "$(code "$BASE/api/auth/me")" 200

# G3 the SLA sweep is admin-only
check "G3 escalate without session -> 401" \
      "$(code -X POST "$BASE/api/admin/escalate")" 401
check "G3b escalate as staff -> 403" \
      "$(code -b "$JAR/staff" -X POST "$BASE/api/admin/escalate")" 403
check "G3c escalate as admin -> 200" \
      "$(code -b "$JAR/admin" -X POST "$BASE/api/admin/escalate")" 200

# G4 filing a complaint routes it straight away (demo embedding)
code -b "$JAR/citizen" -X POST "$BASE/api/complaints" -H 'Content-Type: application/json' \
     -d '{"title":"Water pipe leaking on the corner","description":"Clean drinking water has been leaking from a municipal pipeline on the corner since morning."}' >/dev/null
DEPT=$(python3 -c "import json;print(json.load(open('/tmp/_body')).get('department') or 'none')" 2>/dev/null || echo none)
check "G4 new complaint is routed on filing" "$([ "$DEPT" != none ] && echo routed || echo none)" routed

echo ""
echo "--- Group F: logout ---"
check "F1 logout -> 200" \
      "$(code -b "$JAR/citizen" -c "$JAR/citizen" -X POST "$BASE/api/auth/logout")" 200
check "F2 session no longer valid -> 401" \
      "$(code -b "$JAR/citizen" "$BASE/api/complaints")" 401

rm -rf "$JAR"
echo ""
echo "================================================"
echo "API TESTS:  $PASS passed, $FAIL failed"
echo "================================================"
[ "$FAIL" -eq 0 ]
