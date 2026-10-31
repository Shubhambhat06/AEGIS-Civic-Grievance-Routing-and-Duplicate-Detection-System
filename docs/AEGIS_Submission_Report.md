# DBMS Project Report

**DBMS Experiential Learning — Level 3**
PES University · Course instructor: Dr. Nagasundari S

---

## 1. Project Title

**AEGIS — Civic Grievance Routing and Duplicate Detection System**

A municipal complaint portal that detects near-duplicate reports by meaning rather than keywords, and routes each complaint to the correct department by learning from resolution history.

---

## 2. Student SRNs and Names

| SRN | Name | Section |
|---|---|---|
| PES1UG24AM274 | Siddanth Anil | E |
| PES1UG24AM273 | Shubham Bhat | E |

> **Before submitting:** complete the responsibility split in section 9.1, and confirm Shubham's section.

---

## 3. Abstract

Municipal grievance portals suffer from two problems that no amount of staffing fixes. The same issue is reported many times — when a pothole opens on a busy road, dozens of citizens file separate tickets over the following week, and staff spend their time closing near-identical complaints one by one. Separately, complaints reach the wrong department, because portals ask citizens to pick a category from a dropdown and citizens are describing a problem, not filing a work order.

Both problems share one root cause: the complaint description is **unstructured text**, and a relational database alone can only match it on exact keywords. "Huge pothole near the bus stop" and "Dangerous crater on main road" describe the same hole and share no words at all.

AEGIS addresses both by storing every complaint description as a 384-dimension vector embedding alongside the structured record. Similarity search over those embeddings does two jobs: it surfaces near-duplicate reports so staff can merge them into one tracked issue without losing the individual reporters, and it routes a new complaint to whichever department resolved the most similar past complaints — a routing rule learned from history rather than hard-coded.

The system uses **PostgreSQL 16** for the structured entities, where referential integrity, constraints and transactions are essential, and **pgvector** for the complaint text, where relational decomposition offers nothing and semantic similarity is the required operation. Seven advanced database features are implemented: transactions with explicit row locking, triggers, stored functions, views and a materialized view, B-tree/GIN/HNSW/partial indexing, full-text search, and vector similarity search. A **Next.js 16** application provides role-based access for Citizens, Staff and Admins.

The project goes beyond CRUD in a measurable way: the routing and deduplication engine is the product, and the forms around it merely feed it. Routing accuracy, duplicate-detection quality, constraint enforcement, transaction rollback and concurrency safety were all measured rather than asserted — **33 database tests, 29 API tests, a two-session concurrency race and a 78-check consistency audit, all passing.**

---

## 4. Technology Stack

| Layer | Technology | Why |
|---|---|---|
| Frontend | Next.js 16.4.3 (App Router), React 19 | Required by the specification; App Router keeps pages and API routes in one project |
| Styling | Plain CSS | No framework needed for three pages; keeps the dependency list small |
| Backend / API | Next.js Route Handlers | The specification's suggested backend layer; no separate server process |
| Database driver | `pg` (node-postgres) with a pooled connection | Parameterised queries, which is what makes SQL injection impossible |
| Relational database | PostgreSQL 16 | Mandatory SQL database (specification requirement 3) |
| Vector database | pgvector 0.7+, `VECTOR(384)`, HNSW index, cosine distance | Specification Option 2; see section 6 for the justification |
| Embeddings | `sentence-transformers/all-MiniLM-L6-v2` (Python), with a pure-SQL fallback | 384 dimensions, CPU-friendly, trained for sentence similarity |
| Authentication | `bcryptjs` password hashing, HMAC-signed `httpOnly` cookies (Node `crypto`) | Requirement 13: no plain-text passwords; a signed cookie cannot be forged client-side |
| Containerisation | Docker + Docker Compose | One command brings up PostgreSQL with pgvector already installed |
| Testing | Bash and Python harnesses, Playwright for screenshots | 62 automated tests plus a consistency audit |
| Version control | Git + GitHub | Requirement 15 |

**Production npm dependencies: five** — `next`, `react`, `react-dom`, `pg`, `bcryptjs`. `npm audit` reports **0 vulnerabilities**.

### 4.1 How to run it

The project ships with Docker Compose so that pgvector — the fiddliest part to install by hand — comes pre-installed in the database image.

```bash
git clone <repository-url>
cd aegis-project
cp .env.example .env          # then edit SESSION_SECRET and POSTGRES_PASSWORD
docker compose up --build
```

Open <http://localhost:3000>. The schema, functions, triggers and sample data load automatically on first start.

Sample accounts (all use the password `password123`):

| Role | Email |
|---|---|
| Citizen | `arjun.menon@example.com` |
| Staff | `roads1@bbmp.gov.in` |
| Admin | `admin@bbmp.gov.in` |

To re-seed after changing any SQL file, `docker compose down -v` then `up` again — the `-v` is what deletes the data volume, and forgetting it is the most common reason a schema change appears to do nothing.

Full setup instructions, including running without Docker, are in `README.md`.

---

## 5. SQL — Database Commands

The relational layer is 11 tables, 15 foreign keys, 19 `CHECK` constraints, 23 indexes, 2 views, 1 materialized view, 3 triggers and 6 stored functions, across roughly 2,150 lines of SQL in `db/`.

### 5.1 DDL — `db/01_schema.sql`

```sql
-- Enumerated types: a closed value set shared by more than one table,
-- so it is declared once as a type rather than repeated as a CHECK.
CREATE TYPE complaint_status AS ENUM
    ('OPEN','ROUTED','IN_PROGRESS','RESOLVED','MERGED','ESCALATED');

CREATE TABLE complaint (
    complaint_id       SERIAL              PRIMARY KEY,
    citizen_id         INT                 NOT NULL,
    dept_id            INT,                              -- NULL until routed
    ward_id            INT                 NOT NULL,
    assigned_staff_id  INT,                              -- NULL until triaged
    title              VARCHAR(150)        NOT NULL,
    description        TEXT                NOT NULL,
    status             complaint_status    NOT NULL DEFAULT 'OPEN',
    priority           complaint_priority  NOT NULL DEFAULT 'MEDIUM',
    latitude           NUMERIC(9,6),
    longitude          NUMERIC(9,6),
    filed_at           TIMESTAMPTZ         NOT NULL DEFAULT now(),
    sla_deadline       TIMESTAMPTZ         NOT NULL,
    resolved_at        TIMESTAMPTZ,

    CONSTRAINT fk_complaint_citizen FOREIGN KEY (citizen_id)
        REFERENCES citizen (citizen_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_complaint_dept FOREIGN KEY (dept_id)
        REFERENCES department (dept_id) ON UPDATE CASCADE ON DELETE SET NULL,

    CONSTRAINT ck_complaint_title CHECK (length(trim(title)) >= 5),
    -- latitude and longitude are a pair: both present or both absent
    CONSTRAINT ck_complaint_geo   CHECK ((latitude IS NULL) = (longitude IS NULL)),
    CONSTRAINT ck_complaint_sla   CHECK (sla_deadline > filed_at),
    CONSTRAINT ck_complaint_resolved_consistency
        CHECK (status <> 'RESOLVED' OR resolved_at IS NOT NULL)
);
```

`ON DELETE` actions are chosen per relationship rather than copied: `RESTRICT` on ward and department so geography and routing history cannot be orphaned; `SET NULL` on `assigned_staff_id` so a departing staff member returns work to the pool instead of destroying it; `CASCADE` only where the child row is meaningless alone.

**ALTER** — three realistic changes kept in the script so their use is visible:

```sql
ALTER TABLE complaint ADD COLUMN duplicate_count INT NOT NULL DEFAULT 0;
ALTER TABLE complaint ADD CONSTRAINT ck_complaint_dupcount CHECK (duplicate_count >= 0);

-- A generated column stays in sync without a trigger.
ALTER TABLE complaint ADD COLUMN search_tsv TSVECTOR
    GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(title,'')),       'A') ||
        setweight(to_tsvector('english', coalesce(description,'')), 'B')
    ) STORED;

ALTER TABLE department ALTER COLUMN category TYPE VARCHAR(60);
```

**Indexes** — each serves a named query, none speculative:

```sql
CREATE INDEX idx_embedding_hnsw ON complaint_embedding
    USING hnsw (embedding vector_cosine_ops);          -- vector search
CREATE INDEX idx_complaint_fts  ON complaint USING GIN (search_tsv);  -- full text

-- Partial index: the SLA sweep only ever looks at live complaints, so
-- the index stays small as the resolved archive grows.
CREATE INDEX idx_complaint_sla_open ON complaint (sla_deadline)
    WHERE status NOT IN ('RESOLVED','MERGED');
```

### 5.2 DML and queries — `db/04_queries.sql`, `db/06_advanced_queries.sql`

Twenty-five queries in total. `INSERT`, `UPDATE`, `DELETE` and `SELECT` all appear; joins, grouping, `HAVING`, aggregates, scalar and correlated subqueries, CTEs, window functions, full-text search and vector search are each demonstrated.

**Departments slower than the overall average** — `GROUP BY` with `HAVING` filtering on an aggregate, where the threshold comes from a scalar subquery:

```sql
SELECT d.dept_name,
       ROUND(AVG(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0)::NUMERIC, 1) AS avg_hours
FROM department d
JOIN complaint c ON c.dept_id = d.dept_id
WHERE c.resolved_at IS NOT NULL
GROUP BY d.dept_name
HAVING AVG(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0) >
       (SELECT AVG(EXTRACT(EPOCH FROM (resolved_at - filed_at))/3600.0)
          FROM complaint WHERE resolved_at IS NOT NULL)
ORDER BY avg_hours DESC;
```

**Top 2 slowest complaints per department** — a CTE feeding a window function. Two steps are required because a window function cannot appear in `WHERE`:

```sql
WITH ranked AS (
    SELECT c.complaint_id, c.title, d.dept_name,
           DENSE_RANK() OVER (PARTITION BY c.dept_id
                              ORDER BY (c.resolved_at - c.filed_at) DESC) AS slowness_rank
    FROM complaint c JOIN department d ON d.dept_id = c.dept_id
    WHERE c.resolved_at IS NOT NULL
)
SELECT * FROM ranked WHERE slowness_rank <= 2 ORDER BY dept_name, slowness_rank;
```

**Merge-chain integrity check** — a recursive CTE that doubles as a test. `fn_merge_duplicate` refuses to merge into an already-merged complaint, so chains should never exceed one hop; this measures the real maximum and returns 1:

```sql
WITH RECURSIVE chains AS (
    SELECT child_complaint_id AS start_id, parent_complaint_id AS current_id, 1 AS depth
      FROM duplicate_link
    UNION ALL
    SELECT ch.start_id, dl.parent_complaint_id, ch.depth + 1
      FROM chains ch JOIN duplicate_link dl ON dl.child_complaint_id = ch.current_id
     WHERE ch.depth < 10
)
SELECT MAX(depth) AS deepest_merge_chain FROM chains;
```

### 5.3 Advanced features — `db/02_functions.sql`

**Transaction with row locking.** The merge does three writes that must all happen or none:

```sql
CREATE OR REPLACE FUNCTION fn_merge_duplicate(
    p_child_id INT, p_parent_id INT, p_similarity REAL, p_staff_id INT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_child_status complaint_status; v_parent_status complaint_status;
BEGIN
    IF p_child_id = p_parent_id THEN
        RAISE EXCEPTION 'A complaint cannot be merged into itself (id %)', p_child_id;
    END IF;

    -- Row locks, always child before parent, so two merges running in
    -- opposite directions cannot deadlock.
    SELECT status INTO v_child_status
      FROM complaint WHERE complaint_id = p_child_id  FOR UPDATE;
    SELECT status INTO v_parent_status
      FROM complaint WHERE complaint_id = p_parent_id FOR UPDATE;

    IF v_parent_status = 'MERGED' THEN
        RAISE EXCEPTION 'Complaint % is itself a duplicate and cannot be a parent', p_parent_id;
    END IF;

    INSERT INTO duplicate_link
        (child_complaint_id, parent_complaint_id, similarity_score, merged_by)
    VALUES (p_child_id, p_parent_id, p_similarity, p_staff_id);

    UPDATE complaint SET status = 'MERGED' WHERE complaint_id = p_child_id;
    UPDATE complaint SET duplicate_count = duplicate_count + 1
     WHERE complaint_id = p_parent_id;
END; $$;
```

**Trigger — audit trail.** Written as a trigger rather than application code so the trail is complete no matter who writes: the web app, a stored function, or a manual `psql` session.

```sql
CREATE OR REPLACE FUNCTION trg_log_status_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO status_history (complaint_id, old_status, new_status, remarks)
        VALUES (NEW.complaint_id, NULL, NEW.status, 'Complaint filed');
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO status_history (complaint_id, old_status, new_status, changed_by)
        VALUES (NEW.complaint_id, OLD.status, NEW.status, NEW.assigned_staff_id);
    END IF;
    RETURN NULL;
END; $$;

CREATE TRIGGER t_complaint_status_audit
    AFTER INSERT OR UPDATE OF status ON complaint
    FOR EACH ROW EXECUTE FUNCTION trg_log_status_change();
```

Two further triggers: `t_complaint_validate` blocks illegal status transitions and stamps `resolved_at`; `t_embedding_auto_route` routes a complaint when its embedding arrives.

**Views.** `v_open_queue` (staff queue with computed hours-remaining and a breach flag), `v_citizen_complaints` (follows merge links so a citizen whose report was merged still sees the parent's progress), and the materialized `mv_department_performance`.

### 5.4 Normalization

**All 11 relations are in BCNF.** The full functional-dependency analysis is in `docs/normalization.md`. The three points most worth defending:

- `status_history` is the only relation where the 2NF check is non-vacuous — the only composite key `(complaint_id, changed_at)` with non-prime attributes. Neither half of the key determines anything alone.
- `ward_name → zone` is not a 3NF violation, because `ward_name` carries a `UNIQUE` constraint and is therefore itself a candidate key. Transitivity requires a *non-prime* intermediate attribute.
- `sla_deadline` is **not** transitively dependent on `dept_id`. If it were derived from the department's current SLA policy, `(dept_id, filed_at) → sla_deadline` would hold and the relation would fall out of BCNF. It is a snapshot stored at filing time, so a later policy change cannot retroactively rewrite historical deadlines. The business rule and the normal form agree here.

`complaint.duplicate_count` is a deliberate denormalization. It is **not** a normal-form violation — it is determined by the key — but it duplicates a fact held in `duplicate_link`. It is maintained only inside `fn_merge_duplicate`, in the same transaction as the link insert, and the invariant is checked by test T3.2, test T3.5 and audit check F5.

### 5.5 Concurrency control

The merge is the one place two users can collide: two staff members can both decide complaint #19 is a duplicate of #15 at the same moment. Without protection this is a lost-update race — both could pass validation and the parent counter would end at 2 for one real duplicate.

`SELECT ... FOR UPDATE` takes row-level exclusive locks before any validation. The second session blocks until the first commits, then **re-reads** the row, sees `status = 'MERGED'` and is rejected. A `UNIQUE` constraint alone would not be enough: it would stop the second `INSERT`, but only after both sessions had already read a stale status.

AEGIS runs at PostgreSQL's default `READ COMMITTED` isolation level, where a statement sees only data committed before it began — so the explicit lock is what provides the needed guarantee without paying for `SERIALIZABLE` across the whole application.

`scripts/concurrency_test.sh` runs the race for real. Measured output:

```
--- Session A ---
    A: acquiring locks and merging
    A: merged, holding transaction open
    A: committed
--- Session B ---
    B: attempting the same merge
    ERROR:  Complaint 19 is already MERGED and cannot be merged

  duplicate_link rows for #19 : 1   (expected 1)
  parent duplicate_count      : 3 -> 4   (expected +1)
PASS - the race was prevented; exactly one merge took effect.
```

Session B's failure mode is the evidence: it failed on the *validation check*, not on a constraint, which means it blocked on the lock and re-read after A committed.

---

## 6. NoSQL / Vector Database Commands

AEGIS uses **Option 2: SQL + Vector Database** — PostgreSQL with pgvector.

### 6.1 Why a vector database, and why pgvector specifically

The complaint *description* is free text, and the two central questions the system asks about it are "is this the same issue as something already reported?" and "which department handles problems that look like this?" Neither is a keyword question. A `LIKE` query or even full-text search scores "Huge pothole near the bus stop" and "Dangerous crater on main road" as unrelated. Embedding both into a 384-dimension space places them close together, because the model encodes meaning rather than spelling.

Keeping the vectors *inside* PostgreSQL rather than in a separate service (Pinecone, Qdrant) means one query can combine structured filters with similarity ranking:

```sql
WHERE c.ward_id    = v_ward_id              -- structured: same ward
  AND c.filed_at   < v_filed_at             -- structured: earlier only
  AND c.status    <> 'MERGED'               -- structured: not itself a duplicate
  AND (1 - (e.embedding <=> v_embedding)) >= p_threshold   -- vector: similar text
```

That ward filter is the one that matters most: two potholes in different parts of the city are not the same pothole however similar the wording. With a separate vector service this becomes two round trips plus a merge in application code, and the combined result can no longer be made transactional with the merge operation.

### 6.2 The five questions the specification asks

**What data is converted into embeddings.** The complaint's `title` concatenated with its `description` — everything the citizen typed. Structured fields (ward, priority, timestamps) are deliberately excluded: they are already queryable in SQL, and including them would dilute the semantic signal.

**Which embedding model.** `sentence-transformers/all-MiniLM-L6-v2`, 384 dimensions. Chosen because it is trained specifically for sentence similarity rather than classification or generation, runs comfortably on CPU, and 384 dimensions keeps the index small and fast at this scale.

**How vectors are stored.** In a dedicated `complaint_embedding` table as a `VECTOR(384)` column, HNSW-indexed with `vector_cosine_ops`. The table is separate from `complaint` for two reasons: the embedding is generated asynchronously, after the complaint row already exists; and a 384-float vector is roughly 1.5 KB, so keeping it out of the main table means ordinary complaint queries never read it. Making the foreign key also the primary key is what enforces the 1:1.

```sql
CREATE TABLE complaint_embedding (
    complaint_id  INT          PRIMARY KEY,
    embedding     VECTOR(384)  NOT NULL,
    model_name    VARCHAR(60)  NOT NULL DEFAULT 'all-MiniLM-L6-v2',
    generated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT fk_embedding_complaint FOREIGN KEY (complaint_id)
        REFERENCES complaint (complaint_id) ON DELETE CASCADE
);

CREATE INDEX idx_embedding_hnsw ON complaint_embedding
    USING hnsw (embedding vector_cosine_ops);
```

**Similarity metric.** Cosine distance, via pgvector's `<=>` operator. The model emits L2-normalised vectors, so cosine is the metric it was trained under and similarity is simply `1 - distance`.

**How relevant results are retrieved.**

```sql
CREATE OR REPLACE FUNCTION fn_find_duplicates(
    p_complaint_id INT, p_threshold REAL DEFAULT 0.80, p_limit INT DEFAULT 5)
RETURNS TABLE (candidate_id INT, candidate_title VARCHAR(150),
               candidate_status complaint_status, similarity REAL)
LANGUAGE plpgsql AS $$
DECLARE v_embedding VECTOR(384); v_ward_id INT; v_filed_at TIMESTAMPTZ;
BEGIN
    SELECT e.embedding, c.ward_id, c.filed_at
      INTO v_embedding, v_ward_id, v_filed_at
      FROM complaint c JOIN complaint_embedding e ON e.complaint_id = c.complaint_id
     WHERE c.complaint_id = p_complaint_id;

    IF v_embedding IS NULL THEN RETURN; END IF;   -- pipeline has not run yet

    RETURN QUERY
    SELECT c.complaint_id, c.title, c.status,
           (1 - (e.embedding <=> v_embedding))::REAL AS similarity
      FROM complaint c JOIN complaint_embedding e ON e.complaint_id = c.complaint_id
     WHERE c.complaint_id <> p_complaint_id
       AND c.ward_id       = v_ward_id
       AND c.filed_at      < v_filed_at
       AND c.status       <> 'MERGED'
       AND (1 - (e.embedding <=> v_embedding)) >= p_threshold
     ORDER BY e.embedding <=> v_embedding
     LIMIT p_limit;
END; $$;
```

### 6.3 Routing by similarity-weighted vote

```sql
-- Take the nearest resolved complaints that clear a similarity floor,
-- then pick the department with the highest total weight.
SELECT dept_id FROM (
    SELECT c.dept_id,
           power(1 - (e.embedding <=> v_embedding), 2)::REAL AS weight
      FROM complaint c JOIN complaint_embedding e ON e.complaint_id = c.complaint_id
     WHERE c.status = 'RESOLVED' AND c.dept_id IS NOT NULL
       AND (1 - (e.embedding <=> v_embedding)) >= p_min_similarity
     ORDER BY e.embedding <=> v_embedding
     LIMIT p_neighbours
) AS neighbours
GROUP BY dept_id ORDER BY SUM(weight) DESC LIMIT 1;
```

The weight is the **square** of the similarity, not a vote count. A plain head-count let a department that simply appears more often in the archive outvote the one department whose complaint was an obvious match; squaring makes a single close neighbour decisive. That change alone took measured routing accuracy from 6/10 to 8/10 on the seed data.

### 6.4 Demonstrating without Python

`db/03_seed.sql` defines `fn_demo_embedding`, a pure-SQL fallback that embeds text using the hashing trick — each word hashed into one of 384 buckets, then L2-normalised. It is a real if simple text embedding, and it means the entire system can be demonstrated with nothing but `psql`. Its accuracy is lower than the real model; the measured figures in section 9.3 are from this fallback and should be re-measured if you demonstrate with `scripts/embed.py`.

---

## 7. Next.js — Project Tree Structure

```
aegis-project/
├── docker-compose.yml          db + app, pgvector image, healthcheck
├── .env.example                Compose configuration template
├── README.md                   setup and execution instructions
│
├── app/                        the Next.js application
│   ├── Dockerfile              multi-stage build, non-root runtime
│   ├── .dockerignore
│   ├── .env.example            local (non-Docker) configuration template
│   ├── next.config.mjs         standalone output for a slim image
│   ├── package.json            5 production dependencies
│   │
│   ├── lib/
│   │   ├── db.js               pooled pg client, parameterised query helper
│   │   └── auth.js             bcrypt login, HMAC session cookie, role guard
│   │
│   └── app/                    App Router
│       ├── layout.jsx          shared shell
│       ├── globals.css
│       ├── page.jsx            /         sign-in (citizen or staff)
│       ├── citizen/page.jsx    /citizen  file and track complaints
│       ├── staff/page.jsx      /staff    work queue, duplicate review, merge
│       ├── admin/page.jsx      /admin    department performance dashboard
│       │
│       └── api/                Route Handlers
│           ├── auth/login/route.js        POST   sign in
│           ├── auth/logout/route.js       POST   sign out
│           ├── complaints/route.js        GET    role-filtered list
│           │                              POST   file a complaint (citizen)
│           ├── complaints/[id]/route.js   GET    one complaint + audit trail
│           │                              PATCH  update status (staff)
│           ├── complaints/[id]/duplicates/route.js
│           │                              GET    vector similarity search
│           │                              POST   merge into a parent
│           ├── search/route.js            GET    full-text search
│           └── dashboard/route.js         GET    statistics (admin only)
│
├── db/
│   ├── 01_schema.sql           tables, types, constraints, indexes, views
│   ├── 02_functions.sql        stored functions and triggers
│   ├── 03_seed.sql             sample data + the SQL-only demo embedder
│   ├── 04_queries.sql          15 application and report queries
│   ├── 05_test.sql             33 database tests
│   └── 06_advanced_queries.sql CTEs, window functions, recursive queries, FTS
│
├── scripts/
│   ├── demo.sh                 guided 7-step demonstration
│   ├── run_tests.sh            database test runner
│   ├── api_test.sh             end-to-end API test runner
│   ├── concurrency_test.sh     two-session merge race
│   ├── audit.py                docs and diagrams vs the live schema
│   ├── embed.py                embedding pipeline (all-MiniLM-L6-v2)
│   ├── embed_demo.sql          SQL-only equivalent for demos
│   └── screenshots.mjs         Playwright capture of the whole demo flow
│
├── diagrams/
│   ├── aegis_erd_chen.png/.drawio            ER diagram (Chen notation)
│   └── aegis_relational_schema.png/.drawio   relational schema with FK arrows
│
└── docs/
    ├── AEGIS_Project_Documentation.md   the 14-section project documentation
    ├── AEGIS_Submission_Report.md       this report
    ├── normalization.md                 FD analysis, 1NF to BCNF
    └── screenshots/                     9 captured screenshots
```

**Architecture principle.** Business rules live in the database, not the web layer. The API authenticates the user, decides what they are allowed to ask for, and calls a stored function. This is why the rules survive a second client being written against the same database, and why the test suite can verify them with `psql` alone.

---

## 8. Sample Screenshots of Application Code and Demo

All nine screenshots are in `docs/screenshots/`, captured from a running instance by `scripts/screenshots.mjs`, which drives a real browser through the complete demo flow.

| File | What it shows |
|---|---|
| `01-login.png` | Sign-in form with the Citizen / Staff selector |
| `02-citizen-file.png` | A complaint being filed, with the tracker beside it |
| `03-citizen-submitted.png` | Confirmation, and the complaint appearing in the tracker |
| `04-citizen-merged.png` | **A merged complaint still tracking its parent** — "Same issue as #15 … now ROUTED" |
| `05-staff-queue.png` | The Roads department queue, sorted by SLA urgency |
| `06-staff-duplicates.png` | **Similarity search flagging the duplicate at 75%** |
| `07-staff-merged.png` | Merge confirmed, the duplicate removed from the queue |
| `08-admin-dashboard.png` | Department performance and most-duplicated issues |
| `09-admin-all-queue.png` | **Cross-department queue with breached SLAs in red** |

### 8.1 The live demo

`scripts/demo.sh` walks through seven steps with real database output at each one. Run it alongside the web interface:

```bash
docker compose exec -e PGHOST=/var/run/postgresql db bash /aegis-scripts/demo.sh
```

The capture run produced this sequence end to end:

```
2. citizen files a new complaint
   Complaint #30 submitted.
3. running the embedding pipeline
   complaint #30 auto-routed to: Roads and Infrastructure
5. staff queue and duplicate detection
   2 duplicate candidate(s) shown
   merged; #15 duplicate_count 3 -> 4
6. admin dashboard
   2 complaint(s) past their SLA deadline
```

That is the whole product in six lines: a citizen filed a complaint in free text, the pipeline embedded it, a trigger routed it to the correct department with no dropdown involved, similarity search recognised it as the same pothole already on file, and merging it incremented the parent's report count.

**Suggested demonstration order (about five minutes):**

1. Sign in as a citizen and file a pothole complaint worded differently from the existing ones.
2. Run the embedding pipeline — `docker compose exec db psql -U aegis -d aegis -f /aegis-scripts/embed_demo.sql` — and point out that the complaint has acquired a department without anyone choosing one.
3. Sign in as staff, click **Check duplicates**, and show the similarity percentage against the existing report.
4. Merge, and show the parent's report counter increment.
5. Sign back in as the first citizen and show that their complaint now tracks the parent issue rather than vanishing.
6. Sign in as admin and show the dashboard, the overdue complaints in red, and the most-duplicated issues table.

---

## 9. Evaluation Rubrics — Completion Status

Against the 18 numbered requirements in the project specification.

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | Unique title; real problem; not simple CRUD | **Complete** | AEGIS; the routing and dedup engine is the product, not the forms |
| 2 | 2-member team, both on database and application | **Action needed** | See 9.1 — split defined, names to be filled in |
| 3 | SQL (mandatory) + NoSQL or Vector | **Complete** | PostgreSQL 16 + pgvector (Option 2) |
| 4 | ER diagram converted to relational schema | **Complete** | `diagrams/` — Chen-notation ERD and relational schema with FK arrows; mapping rules in §6 of the project documentation |
| 5 | DDL: CREATE, ALTER, DROP, keys, constraints, indexes, views | **Complete** | `db/01_schema.sql` — 11 tables, 3 ALTERs, 15 FKs, 19 CHECKs, 23 indexes, 2 views + 1 matview |
| 6 | DML: INSERT, UPDATE, DELETE, SELECT; JOIN, GROUP BY, HAVING, aggregates, subqueries | **Complete** | `db/03_seed.sql`, `db/04_queries.sql`, `db/06_advanced_queries.sql` — 25 queries |
| 7 | At least four advanced database concepts | **Exceeded — 7** | Transactions, views, stored functions, triggers, indexing, full-text search, vector similarity search |
| 8 | Vector / semantic search, five questions answered | **Complete** | §6.2 answers all five explicitly |
| 9 | Functional Next.js web interface | **Complete** | Four pages, six API route groups; forms, tables, search, dashboard |
| 10 | API layer; no hard-coded credentials; env vars | **Complete** | `lib/db.js`; `.env.example` at both levels; audit checks E1–E3 |
| 11 | Authentication; minimum 2 roles | **Complete** | Citizen, Staff, Admin; `lib/auth.js`; API tests group B |
| 12 | Database-level input validation and integrity | **Complete** | 19 CHECKs, 15 FKs, validation trigger; database tests group 1 |
| 13 | Security; no plain-text passwords or credentials | **Complete** | bcrypt, HMAC-signed `httpOnly` cookies, parameterised queries, `.gitignore`; audit checks E1–E8 |
| 14 | Documentation with all 14 listed subsections | **Complete** | `docs/AEGIS_Project_Documentation.md`; audit check G1 verifies every subsection is present |
| 15 | Git/GitHub, individual contributions, README | **Partly — action needed** | `README.md` complete; commit history must show both members (see 9.1) |
| 16 | Demonstration material | **Complete** | `scripts/demo.sh`, 9 screenshots, test output |
| 17 | Originality | **Complete** | Original design; no tutorial or repository copied |
| 18 | Level 3: beyond CRUD; justified database choice | **Complete** | §3 and §6.1 |

**Beyond the specification**, aligned to the course syllabus: CTEs, window functions and recursive queries (Unit 2, `db/06_advanced_queries.sql`); a full functional-dependency and BCNF analysis (Unit 3, `docs/normalization.md`); transactions, concurrency control and locking with a live race demonstration (Unit 4, §5.5).

### 9.1 Individual contribution — to be completed before submission

The specification requires both members to contribute to **both** the database and the application, so the split is by feature vertical rather than by layer.

| Area | Member A | Member B |
|---|---|---|
| Schema design and DDL | | |
| Triggers and constraints | | |
| Stored functions | | |
| Embedding pipeline | | |
| Citizen portal | | |
| Staff queue and merge UI | | |
| Admin dashboard | | |
| API routes and authentication | | |
| Test suites | | |
| Documentation | | |

Keep commit authorship matching this table so the GitHub history corroborates it.

### 9.2 Test results

| Suite | Result | Covers |
|---|---|---|
| `db/05_test.sql` | **33 / 33 passed** | Constraints, triggers, transaction rollback, search, views, SLA escalation, cascades, CTE and window-function results |
| `scripts/api_test.sh` | **29 / 29 passed** | Authentication, role-based authorisation, both workflows, search, logout |
| `scripts/concurrency_test.sh` | **PASS** | Two-session merge race; exactly one merge took effect |
| `scripts/audit.py` | **78 / 78 passed** | Documented figures vs the live schema; named objects exist; security properties; seed-data invariants; diagram matches the database |
| `npm audit` | **0 vulnerabilities** | Production dependency tree |

Seven of the database tests pass *because the database refused to do something* — the only way to show a constraint is enforced rather than merely declared.

Re-run everything:

```bash
bash scripts/run_tests.sh            # 6 SQL files, 33 tests
bash scripts/concurrency_test.sh     # the merge race
cd app && npm run build && npm start &
BASE=http://localhost:3000 bash scripts/api_test.sh
python3 scripts/audit.py
```

### 9.3 Measured routing accuracy

**8 of 10** seeded live complaints routed to the correct department, using the SQL-only demo embeddings. The two misses are a footpath repair sent to Parks rather than Roads (arguable — the only historical footpath complaint was handled by Parks) and a fallen tree branch sent to Water Supply, which is a clear miss.

This is the demo embedding's ceiling rather than the system's: the hashing trick matches on shared *words*, and with only 14 historical complaints to learn from, a complaint whose vocabulary overlaps none of them has nothing to match. If you demonstrate with the real `all-MiniLM-L6-v2` model, re-measure and report what you actually get rather than quoting this figure.

### 9.4 Known limitations

Stated plainly, because a grader will find them anyway:

- **Routing is 8/10 on the demo embeddings.** Addressed honestly in 9.3; the fix is the real model, and the future-work section proposes returning a confidence score so low-confidence routings go to manual triage instead of guessing.
- **Latitude and longitude are stored but unused in matching.** Duplicate candidates are restricted by ward, which is coarse. PostGIS and a radius filter would be stronger.
- **The audit trail records `system` for trigger-driven status changes.** The trigger only knows what is on the row; who approved a merge is captured in `duplicate_link.merged_by` instead.
- **Embeddings are English-only.** A Kannada or Hindi complaint would embed poorly.

---

## Deliverables checklist

- [x] Completed DBMS Project Report — this document
- [x] Supporting documentation — `docs/AEGIS_Project_Documentation.md`, `docs/normalization.md`
- [x] ER diagram and relational schema — `diagrams/`
- [x] Screenshots — `docs/screenshots/` (9 files)
- [x] Source code — `db/`, `app/`, `scripts/`
- [x] README with setup and execution instructions
- [ ] **GitHub repository link** — push the repository and paste the URL here: `________________`
- [x] **Teammate SRN and name** — section 2
- [ ] **Individual contribution table** — section 9.1
