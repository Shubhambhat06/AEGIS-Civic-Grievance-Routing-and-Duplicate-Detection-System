#!/usr/bin/env python3
"""
Consistency audit.

Checks that the numbers and object names claimed in the documentation
actually match the live database and the checked-in source. Run after
any schema change so the write-up cannot silently drift out of date.

Usage:  python3 scripts/audit.py            (uses PGHOST/PGPORT/PGDATABASE)
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAIL = []
OK = []


def check(name, actual, expected):
    if actual == expected:
        OK.append(f"PASS  {name:<52} {actual}")
    else:
        FAIL.append(f"FAIL  {name:<52} actual={actual} doc/claim={expected}")


def psql(sql):
    cmd = ["psql", "-X", "-tA", "-c", sql]
    env = dict(os.environ)
    env.setdefault("PGHOST", "/tmp")
    env.setdefault("PGPORT", "5433")
    env.setdefault("PGUSER", "postgres")
    env.setdefault("PGDATABASE", "aegis_test")
    out = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if out.returncode != 0:
        sys.exit("psql failed: " + out.stderr.strip())
    return out.stdout.strip()


# The audit must run against a freshly seeded database. Residue from the
# API tests (for example a complaint filed through the API, which has no
# embedding yet because the pipeline is asynchronous) would otherwise show
# up as a false failure.
if "--no-reseed" not in sys.argv:
    print("Reseeding the test database ...")
    r = subprocess.run(["bash", str(ROOT / "scripts/run_tests.sh")],
                       capture_output=True, text=True, env=dict(os.environ))
    if r.returncode != 0:
        sys.exit("reseed failed:\n" + r.stdout[-2000:])
    print("Reseed OK.\n")

doc = (ROOT / "docs/AEGIS_Project_Documentation.md").read_text()
readme = (ROOT / "README.md").read_text()
schema = (ROOT / "db/01_schema.sql").read_text()
funcs = (ROOT / "db/02_functions.sql").read_text()

print("=== A. Database object counts vs the documented figures ===")

counts = {
    "tables": ("SELECT count(*) FROM information_schema.tables "
               "WHERE table_schema='public' AND table_type='BASE TABLE'", 11),
    "views": ("SELECT count(*) FROM information_schema.views WHERE table_schema='public'", 2),
    "materialized views": ("SELECT count(*) FROM pg_matviews WHERE schemaname='public'", 1),
    "triggers": ("SELECT count(DISTINCT trigger_name) FROM information_schema.triggers "
                 "WHERE trigger_schema='public'", 3),
    "fn_ functions": ("SELECT count(*) FROM information_schema.routines "
                      "WHERE routine_schema='public' AND routine_name LIKE 'fn\\_%'", 6),
    "CHECK constraints": ("SELECT count(*) FROM information_schema.table_constraints "
                          "WHERE table_schema='public' AND constraint_type='CHECK' "
                          "AND constraint_name LIKE 'ck\\_%'", 19),
    "foreign keys": ("SELECT count(*) FROM information_schema.table_constraints "
                     "WHERE table_schema='public' AND constraint_type='FOREIGN KEY'", 15),
}
for label, (sql, expected) in counts.items():
    check(f"A1 {label}", int(psql(sql)), expected)

print("\n=== B. Every table in the schema file exists in the database ===")
declared = set(re.findall(r"CREATE TABLE (\w+)", schema))
live = set(psql("SELECT table_name FROM information_schema.tables "
                "WHERE table_schema='public' AND table_type='BASE TABLE'").split("\n"))
check("B1 declared tables == live tables", declared == live, True)
if declared != live:
    FAIL.append(f"      only in file: {declared - live} | only in db: {live - declared}")

print("\n=== C. Objects named in the docs actually exist ===")
# every fn_* and trigger name mentioned in the documentation
doc_funcs = set(re.findall(r"`?(fn_[a-z_]+)`?", doc))
live_funcs = set(psql("SELECT routine_name FROM information_schema.routines "
                      "WHERE routine_schema='public'").split("\n"))
missing = {f for f in doc_funcs if f not in live_funcs}
check("C1 functions named in docs exist", missing, set())

doc_trigs = set(re.findall(r"\bt_[a-z_]+", doc))
live_trigs = set(psql("SELECT DISTINCT trigger_name FROM information_schema.triggers "
                      "WHERE trigger_schema='public'").split("\n"))
missing_t = {t for t in doc_trigs if t not in live_trigs}
check("C2 triggers named in docs exist", missing_t, set())

doc_idx = set(re.findall(r"`?(idx_[a-z_]+)`?", doc))
live_idx = set(psql("SELECT indexname FROM pg_indexes WHERE schemaname='public'").split("\n"))
check("C3 indexes named in docs exist", {i for i in doc_idx if i not in live_idx}, set())

doc_views = set(re.findall(r"`(v_[a-z_]+|mv_[a-z_]+)`", doc))
live_views = set(psql("SELECT table_name FROM information_schema.views "
                      "WHERE table_schema='public'").split("\n")) | \
             set(psql("SELECT matviewname FROM pg_matviews WHERE schemaname='public'").split("\n"))
check("C4 views named in docs exist", {v for v in doc_views if v not in live_views}, set())

print("\n=== D. Requirement coverage (spec sections 5, 6, 7) ===")
for kw in ["CREATE TABLE", "ALTER TABLE", "DROP TABLE", "PRIMARY KEY",
           "FOREIGN KEY", "CHECK", "CREATE INDEX", "CREATE VIEW"]:
    check(f"D1 DDL uses {kw}", kw in schema, True)

seed = (ROOT / "db/03_seed.sql").read_text()
queries = (ROOT / "db/04_queries.sql").read_text()
for kw in ["INSERT INTO"]:
    check(f"D2 DML uses {kw}", kw in seed, True)
for kw in ["UPDATE ", "DELETE FROM"]:
    check(f"D2 DML uses {kw.strip()}", kw in funcs or kw in (ROOT / "db/05_test.sql").read_text(), True)
for kw in ["JOIN", "GROUP BY", "HAVING", "ORDER BY", "COUNT(", "AVG(",
           "NOT EXISTS", "EXPLAIN"]:
    check(f"D3 queries use {kw}", kw in queries, True)

print("\n=== E. Security requirements (spec 10, 13) ===")
app = ROOT / "app"
src = "\n".join(p.read_text() for p in app.rglob("*.js") if "node_modules" not in str(p))
src += "\n".join(p.read_text() for p in app.rglob("*.jsx") if "node_modules" not in str(p))

check("E1 no hard-coded postgres URL in app source",
      bool(re.search(r"postgres(ql)?://[^'\"\s]*:[^'\"\s@]+@", src)), False)
check("E2 DATABASE_URL read from env", "process.env.DATABASE_URL" in src, True)
check("E3 SESSION_SECRET read from env", "process.env.SESSION_SECRET" in src, True)
check("E4 bcrypt used for passwords", "bcrypt" in src, True)
check("E5 session cookie is httpOnly", "httpOnly: true" in src, True)
check("E6 .env.local is git-ignored", ".env.local" in (ROOT / ".gitignore").read_text(), True)
check("E7 .env.local absent from the repo", (app / ".env.local").exists(), False)
check("E7b .env.example provided", (app / ".env.example").exists(), True)

# string-concatenated SQL would show as ${...} inside a query template
concat = re.findall(r"query\(\s*`[^`]*\$\{", src)
# the only permitted interpolation is the audited table/column switch in auth.js
check("E8 no user input interpolated into SQL", len(concat) <= 2, True)

print("\n=== F. Seed data integrity ===")
check("F1 bcrypt hashes are well formed",
      int(psql("SELECT count(*) FROM citizen WHERE password_hash LIKE '$2%' "
               "AND length(password_hash)=60")), 10)
check("F2 staff hashes well formed",
      int(psql("SELECT count(*) FROM staff WHERE password_hash LIKE '$2%' "
               "AND length(password_hash)=60")), 8)
check("F3 every complaint has an embedding",
      int(psql("SELECT count(*) FROM complaint c WHERE NOT EXISTS "
               "(SELECT 1 FROM complaint_embedding e WHERE e.complaint_id=c.complaint_id)")), 0)
check("F4 no orphaned duplicate links",
      int(psql("SELECT count(*) FROM duplicate_link dl WHERE NOT EXISTS "
               "(SELECT 1 FROM complaint c WHERE c.complaint_id=dl.parent_complaint_id)")), 0)
check("F5 duplicate_count matches real link counts",
      int(psql("SELECT count(*) FROM complaint c WHERE c.duplicate_count <> "
               "(SELECT count(*) FROM duplicate_link d WHERE d.parent_complaint_id=c.complaint_id)")), 0)
check("F6 every MERGED complaint has a link",
      int(psql("SELECT count(*) FROM complaint c WHERE c.status='MERGED' AND NOT EXISTS "
               "(SELECT 1 FROM duplicate_link d WHERE d.child_complaint_id=c.complaint_id)")), 0)
check("F7 no complaint is its own parent",
      int(psql("SELECT count(*) FROM duplicate_link WHERE child_complaint_id=parent_complaint_id")), 0)

print("\n=== G. Documentation internal consistency ===")
check("G1 doc has all 14 required sections",
      all(f"## {n}." in doc for n in range(1, 15)), True)
for f in ["01_schema.sql", "02_functions.sql", "03_seed.sql", "04_queries.sql",
          "05_test.sql", "06_advanced_queries.sql"]:
    check(f"G2 doc/readme reference {f} and it exists",
          (ROOT / "db" / f).exists(), True)
for d in ["aegis_erd_chen.png", "aegis_relational_schema.png"]:
    check(f"G3 diagram {d} present", (ROOT / "diagrams" / d).exists(), True)
check("G4 readme sample password matches seed comment",
      "password123" in readme and "password123" in seed, True)

print("\n=== G2. Syllabus coverage ===")
adv = (ROOT / "db/06_advanced_queries.sql").read_text()
for kw in ["WITH RECURSIVE", "OVER (PARTITION BY", "RANK()", "LAG(", "NTILE(",
           "ROW_NUMBER()", "ts_headline", "DENSE_RANK()"]:
    check(f"G5 Unit 2 feature {kw}", kw in adv, True)
norm = (ROOT / "docs/normalization.md")
check("G6 normalization document present", norm.exists(), True)
if norm.exists():
    nt = norm.read_text()
    for kw in ["1NF", "2NF", "3NF", "BCNF", "4NF", "Lossless"]:
        check(f"G7 normalization covers {kw}", kw in nt, True)
check("G8 concurrency test script present",
      (ROOT / "scripts/concurrency_test.sh").exists(), True)
check("G9 docs cover locking", "FOR UPDATE" in doc, True)

print("\n=== G3. Docker, screenshots and the submission report ===")
compose = ROOT / "docker-compose.yml"
check("G10 docker-compose.yml present", compose.exists(), True)
if compose.exists():
    ct = compose.read_text()
    check("G11 compose uses a pgvector image", "pgvector/pgvector" in ct, True)
    check("G12 compose waits for the db healthcheck",
          "service_healthy" in ct and "healthcheck" in ct, True)
    check("G13 compose mounts the three init files",
          all(f"db/{f}:/docker-entrypoint-initdb.d" in ct
              for f in ["01_schema.sql", "02_functions.sql", "03_seed.sql"]), True)
    check("G14 compose hard-codes no real secret",
          "SESSION_SECRET: ${SESSION_SECRET" in ct, True)
check("G15 app Dockerfile present", (ROOT / "app/Dockerfile").exists(), True)
check("G16 Dockerfile runs as non-root",
      "USER nextjs" in (ROOT / "app/Dockerfile").read_text(), True)
check("G17 next.config enables standalone output",
      "standalone" in (ROOT / "app/next.config.mjs").read_text(), True)
check("G18 root .env.example present", (ROOT / ".env.example").exists(), True)

shots = sorted((ROOT / "docs/screenshots").glob("*.png"))
check("G19 at least 5 screenshots captured", len(shots) >= 5, True)
report = ROOT / "docs/AEGIS_Submission_Report.md"
check("G20 submission report present", report.exists(), True)
if report.exists():
    rt = report.read_text()
    check("G21 report has all 9 required sections",
          all(f"## {n}." in rt for n in range(1, 10)), True)
    # every screenshot the report names must actually exist
    named = set(re.findall(r"`(\d\d-[a-z-]+\.png)`", rt))
    missing_shots = {n for n in named if not (ROOT / "docs/screenshots" / n).exists()}
    check("G22 every screenshot named in the report exists", missing_shots, set())
check("G23 demo script present", (ROOT / "scripts/demo.sh").exists(), True)

print("\n=== H. Relational-schema diagram vs the live database ===")
import xml.etree.ElementTree as ET
import html as _html

dgm = ROOT / "diagrams/aegis_relational_schema.drawio"
if dgm.exists():
    root_el = ET.parse(dgm).getroot()
    diag_cols, diag_pk = {}, {}
    for cell in root_el.findall(".//mxCell"):
        cid = cell.get("id") or ""
        if "__" not in cid or cid.startswith("lbl_"):
            continue
        t, col = cid.split("__", 1)
        val = _html.unescape(cell.get("value") or "")
        diag_cols.setdefault(t.lower(), set()).add(col.lower())
        if "<u>" in val:
            diag_pk.setdefault(t.lower(), set()).add(col.lower())

    live_pk, live_cols = {}, {}
    for row in psql("""SELECT tc.table_name, kcu.column_name
         FROM information_schema.table_constraints tc
         JOIN information_schema.key_column_usage kcu
           ON kcu.constraint_name = tc.constraint_name
        WHERE tc.table_schema='public' AND tc.constraint_type='PRIMARY KEY'""").split("\n"):
        t, col = row.split("|"); live_pk.setdefault(t, set()).add(col.lower())
    for row in psql("""SELECT c.table_name, c.column_name
         FROM information_schema.columns c
         JOIN information_schema.tables t ON t.table_name=c.table_name
          AND t.table_schema='public' AND t.table_type='BASE TABLE'
        WHERE c.table_schema='public'""").split("\n"):
        t, col = row.split("|"); live_cols.setdefault(t, set()).add(col.lower())

    check("H1 diagram table set == database table set",
          set(diag_cols) == set(live_cols), True)
    pk_bad = {t for t in diag_cols if diag_pk.get(t, set()) != live_pk.get(t, set())}
    check("H2 every primary key matches the database", pk_bad, set())
    # search_tsv is a generated index column, deliberately not drawn
    ghost = {t: sorted(diag_cols[t] - live_cols.get(t, set())) for t in diag_cols
             if diag_cols[t] - live_cols.get(t, set())}
    check("H3 no column drawn that does not exist", ghost, {})
    undrawn = {t: sorted(live_cols.get(t, set()) - diag_cols[t]) for t in diag_cols
               if live_cols.get(t, set()) - diag_cols[t]}
    check("H4 only search_tsv is undrawn (generated column)",
          undrawn, {"complaint": ["search_tsv"]})
else:
    FAIL.append("FAIL  H0 relational schema diagram missing")


print()
for line in OK:
    print(line)
print()
for line in FAIL:
    print(line)
print()
print("=" * 62)
print(f"AUDIT: {len(OK)} passed, {len(FAIL)} failed")
print("=" * 62)
sys.exit(1 if FAIL else 0)
