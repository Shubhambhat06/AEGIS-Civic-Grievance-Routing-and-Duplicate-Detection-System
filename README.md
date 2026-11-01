<div align="center">

# 🛡️ AEGIS

### Civic Grievance Routing and Duplicate Detection System

*Stop the same pothole from becoming thirty tickets, and stop complaints from landing in the wrong department.*

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)
![pgvector](https://img.shields.io/badge/pgvector-HNSW-6E4BD8)
![Next.js](https://img.shields.io/badge/Next.js-16-000000?logo=nextdotjs&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Tests](https://img.shields.io/badge/DB%20tests-33%2F33-brightgreen)
![API tests](https://img.shields.io/badge/API%20tests-29%2F29-brightgreen)
![Normal form](https://img.shields.io/badge/schema-BCNF-blue)

**DBMS Experiential Learning, Level 3 Project · PES University**

</div>

---

## 👥 Team

| Name | SRN |
|---|---|
| **Siddanth Anil** | `PES1UG24AM274` |
| **Shubham Bhat** | `PES1UG24AM273` |

Course instructor: Dr. Nagasundari S

---

## 📑 Table of contents

1. [The problem](#-the-problem)
2. [The solution](#-the-solution)
3. [Key features](#-key-features)
4. [Architecture](#-architecture)
5. [Tech stack](#-tech-stack)
6. [Database design](#-database-design)
7. [Getting started](#-getting-started)
8. [Guided demo](#-guided-demo)
9. [Screenshots](#-screenshots)
10. [Embeddings](#-embeddings-demo-vs-real-model)
11. [API reference](#-api-reference)
12. [Testing](#-testing)
13. [Repository layout](#-repository-layout)
14. [Design decisions](#-design-decisions-worth-knowing)
15. [Future work](#-future-work)
16. [Documentation](#-documentation)

---

## 🧩 The problem

Municipal complaint portals suffer from two chronic problems that have nothing to do with how hard the staff work:

- **The same issue is reported many times.** When a pothole opens on a busy road, dozens of people report it. Each report becomes a separate ticket, staff close them one by one, and the first reporter never learns that thirty neighbours reported the same thing.
- **Complaints reach the wrong department.** Portals make citizens pick a category from a dropdown. Citizens guess wrong, and the complaint sits in the wrong queue with the SLA clock running.

Both share one root cause: a complaint is **unstructured text**, and a conventional database can only match it on exact keywords.

## 💡 The solution

AEGIS treats the complaint description as what it really is, unstructured text. Every complaint is converted into a **384-dimension vector embedding**, which lets the system:

1. **Detect near-duplicates** that share no keywords. *"Huge pothole near the bus stop"* and *"dangerous crater on main road"* are recognised as the same hole, and staff can merge them into a single tracked issue.
2. **Route automatically** by sending a new complaint to the department that resolved the most similar past complaints, instead of trusting a dropdown.

PostgreSQL holds the entities and enforces the rules. pgvector answers the similarity questions SQL alone cannot. They meet in single queries that **filter structurally and rank semantically**.

---

## ✨ Key features

| Area | What you get |
|---|---|
| 🔍 **Duplicate detection** | Cosine-similarity search (pgvector + HNSW), restricted to the same ward, with a staff merge workflow |
| 🧭 **Auto-routing** | Similarity-weighted vote over resolution history, fired by a trigger when an embedding arrives |
| ⏱️ **SLA tracking** | Deadline stored per complaint, with automatic escalation of overdue items |
| 👤 **Citizen portal** | File and track complaints; merged reports show the parent issue's status |
| 🧑‍💼 **Staff queue** | Work queue sorted by SLA urgency, status updates, duplicate review and merge |
| 📊 **Admin dashboard** | Per-department resolution times, breach rates, most-duplicated issues |
| 🔎 **Full-text search** | Weighted `tsvector` with GIN index and `websearch_to_tsquery` |
| 🔐 **Security** | bcrypt passwords, HMAC-signed `httpOnly` cookies, role-based access, parameterised SQL only |
| 🧾 **Audit trail** | Every status change logged by a database trigger, regardless of which client wrote it |

### Complaint lifecycle

```
OPEN ──► ROUTED ──► IN_PROGRESS ──► RESOLVED
  │         │            │
  │         └────────────┴──► ESCALATED   (SLA deadline passed)
  └──────────────────────────► MERGED     (folded into a parent complaint)
```

Illegal transitions (for example reopening a closed complaint, or moving to `IN_PROGRESS` with no assignee) are blocked by a database trigger.

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Browser                                                 │
│  /  (login)   /citizen   /staff   /admin                 │
└───────────────────────┬──────────────────────────────────┘
                        │  fetch(), httpOnly signed cookie
┌───────────────────────▼──────────────────────────────────┐
│  Next.js 16 (App Router)                                 │
│                                                          │
│  Route handlers        lib/auth.js      lib/db.js        │
│  /api/auth/login       bcrypt compare   pg Pool          │
│  /api/complaints       HMAC cookie      parameterised    │
│  /api/complaints/[id]  requireRole()    queries only     │
│  /api/.../duplicates                                     │
│  /api/search                                             │
│  /api/dashboard                                          │
└───────────────────────┬──────────────────────────────────┘
                        │  DATABASE_URL (.env.local or Docker env)
┌───────────────────────▼──────────────────────────────────┐
│  PostgreSQL 16 + pgvector                                │
│                                                          │
│  11 tables · 15 FKs · 19 CHECKs · 23 indexes             │
│  3 triggers · 6 stored functions · 2 views + 1 matview   │
└───────────────────────▲──────────────────────────────────┘
                        │
            scripts/embed.py  (all-MiniLM-L6-v2, CPU)
            writes complaint_embedding → fires auto-routing
```

**Layering principle: business rules live in the database, not the web layer.** The web layer authenticates the user, decides what they may ask for, and calls a stored function. The rules therefore survive a second client being written against the same database, and the test suite can verify them with `psql` alone.

**The embedding pipeline is a separate process.** Generating an embedding needs a Python model that has no place inside a web request. Filing a complaint stays fast, and the complaint waits as `OPEN` until its embedding arrives, at which point the auto-routing trigger fires.

---

## 🧰 Tech stack

| Layer | Technology |
|---|---|
| Database | PostgreSQL 16 |
| Vector search | [pgvector](https://github.com/pgvector/pgvector), `VECTOR(384)`, HNSW index, cosine distance |
| Embedding model | `sentence-transformers/all-MiniLM-L6-v2` |
| Web app and API | Next.js 16 (App Router), React 19 |
| Interface | Indian government portal style after UX4G: tricolour band, bilingual title, Noto Sans, text-size controls (fictional demo, no State Emblem) |
| DB driver | `pg` (node-postgres) |
| Auth | `bcryptjs` + HMAC-signed session cookie |
| Containers | Docker Compose (`pgvector/pgvector:pg16` + Next.js standalone image) |
| Scripts | Python 3.10+, Bash, Playwright |

---

## 🗄️ Database design

### ER diagram and relational schema

| ER diagram (Chen notation) | Relational schema |
|---|---|
| ![ERD](diagrams/aegis_erd_chen.png) | ![Relational schema](diagrams/aegis_relational_schema.png) |

Editable sources are in [`diagrams/`](diagrams) as `.drawio` files.

### Tables

| Table | Purpose |
|---|---|
| `ward` | Geographic units (name, zone) |
| `citizen` | Registered citizens |
| `citizen_phone` | Multivalued phone numbers (keeps `citizen` in 1NF) |
| `department` | Departments with their default SLA hours |
| `staff` | Staff and admin accounts |
| `complaint` | The central entity: text, status, priority, location, SLA deadline |
| `complaint_attachment` | Multivalued attachment URLs |
| `complaint_embedding` | 384-dim vector per complaint, HNSW-indexed |
| `duplicate_link` | Child → parent merge record with similarity score |
| `status_history` | Audit trail written by trigger |
| `feedback` | One citizen rating per complaint |

### Database features

| # | Feature | Where |
|---|---|---|
| 1 | **Transactions and row locking** | `fn_merge_duplicate` uses `SELECT … FOR UPDATE` so two staff cannot merge the same complaint at once |
| 2 | **Views** | `v_open_queue`, `v_citizen_complaints`, materialized `mv_department_performance` |
| 3 | **Stored functions** | `fn_find_duplicates`, `fn_route_complaint`, `fn_merge_duplicate`, `fn_file_complaint`, `fn_escalate_overdue` |
| 4 | **Triggers** | `t_complaint_status_audit`, `t_complaint_validate`, `t_embedding_auto_route` |
| 5 | **Indexing** | B-tree, composite, GIN, HNSW, and two partial indexes (23 total) |
| 6 | **Full-text search** | Generated, weighted `tsvector` column with GIN index |
| 7 | **Vector similarity search** | pgvector HNSW with `vector_cosine_ops` |
| 8 | **CTEs, window functions, recursive queries** | `db/06_advanced_queries.sql` |

### Normalization

All **11 relations are in BCNF**. The one deliberate denormalization, `complaint.duplicate_count`, is not a normal-form violation, since it depends on the key. It is maintained atomically inside the merge function and verified by tests **T3.2** and **T3.5** and by audit check **F5**. The full functional-dependency analysis is in [`docs/normalization.md`](docs/normalization.md).

---

## 🚀 Getting started

There are two ways to run AEGIS. **Docker is recommended**: the database image already has pgvector compiled in, which is the fiddliest part to install by hand.

### Option A: Docker (recommended)

You only need [Docker Desktop](https://www.docker.com/products/docker-desktop/). No local PostgreSQL, Node or Python.

```bash
git clone git@github.com:Shubhambhat06/AEGIS-Civic-Grievance-Routing-and-Duplicate-Detection-System.git
cd AEGIS-Civic-Grievance-Routing-and-Duplicate-Detection-System
cp .env.example .env
```

Edit `.env` and set at least these two values:

| Variable | Description |
|---|---|
| `POSTGRES_PASSWORD` | Database password, anything you like |
| `SESSION_SECRET` | Cookie-signing secret, at least 32 characters |

Then start everything:

```bash
docker compose up --build
```

The first run takes a few minutes. Wait for `aegis-app | ✓ Ready`, then open <http://localhost:3000>. The schema, functions, triggers and sample data load automatically the first time the database container starts.

**Confirm the vector extension loaded:**

```bash
docker compose exec db psql -U aegis -d aegis -c "\dx vector"
docker compose exec db psql -U aegis -d aegis -c "SELECT * FROM fn_find_duplicates(18, 0.3, 5);"
```

**Useful commands**

```bash
docker compose logs -f app                                   # application logs
docker compose exec db psql -U aegis -d aegis                # SQL prompt
docker compose exec db psql -U aegis -d aegis -f /aegis-sql/05_test.sql   # run the DB tests
docker compose down                                          # stop, keep the data
```

> ⚠️ **Re-seeding.** The init scripts run only when the data volume is empty, so editing `db/*.sql` and restarting changes nothing. Use `docker compose down -v` (the `-v` deletes the volume) and then `docker compose up --build`. Forgetting the `-v` is the most common reason a schema change appears to do nothing.

> 💡 **Port already in use?** Set `APP_PORT` or `DB_PORT` in `.env`.

> 🪟 **Windows users.** The repository's `.gitattributes` forces LF line endings, because the shell scripts and SQL files run inside Linux containers, where CRLF causes `$'\r': command not found`. If you cloned before that file existed, run `git add --renormalize .` and commit.

### Option B: Local install

#### Prerequisites

- PostgreSQL 16 or later with the [pgvector](https://github.com/pgvector/pgvector) extension
- Node.js 20 or later
- Python 3.10 or later (only needed for the real embedding model)

#### 1. Clone the repository

```bash
git clone git@github.com:Shubhambhat06/AEGIS-Civic-Grievance-Routing-and-Duplicate-Detection-System.git
cd AEGIS-Civic-Grievance-Routing-and-Duplicate-Detection-System
```

#### 2. Create the database

```bash
createdb aegis
psql -d aegis -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

If `CREATE EXTENSION` fails, pgvector is not installed. On Ubuntu:

```bash
sudo apt install postgresql-16-pgvector
```

#### 3. Load the schema and sample data

Run the files **in order**. The numbering is the dependency order.

```bash
psql -d aegis -f db/01_schema.sql      # tables, constraints, indexes, views
psql -d aegis -f db/02_functions.sql   # stored functions and triggers
psql -d aegis -f db/03_seed.sql        # sample data (24 complaints)
psql -d aegis -f db/04_queries.sql     # 15 report queries (optional, read-only)
psql -d aegis -f db/06_advanced_queries.sql   # CTEs, window functions, FTS (optional)
```

Loading the seed data fires the auto-routing trigger, so complaints arrive already assigned to a department.

#### 4. Configure the application

```bash
cd app
cp .env.example .env.local
```

Edit `.env.local`:

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `PGPOOL_MAX` | Maximum pooled connections (default `10`) |
| `SESSION_SECRET` | Cookie-signing secret, at least 32 characters |

Generate a secret with:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

> `.env.local` is git-ignored and must **never** be committed.

#### 5. Run it

```bash
npm install
npm run dev
```

Open <http://localhost:3000>.

### 🔑 Sample accounts

All seeded accounts use the password `password123`.

| Role | Email | What you see |
|---|---|---|
| Citizen | `arjun.menon@example.com` | File complaints, track your own |
| Staff | `roads1@aegis.example` | Roads department queue, duplicate merging |
| Admin | `admin@aegis.example` | All departments plus the performance dashboard |

> 🎯 **Try this first:** on the sign-in page, choose the sample **Citizen** account and lodge a pothole grievance in your own words. The confirmation gives you a registration number (for example AEG/00025) and tells you straight away which department it went to and whether similar reports exist. Then sign out, choose **Department officer**, and select your grievance in the queue to see the earlier report it matches. That is the feature the whole project is built around.

---

## 🎬 Guided demo

```bash
docker compose exec -e PGHOST=/var/run/postgresql db bash /aegis-scripts/demo.sh
```

This runs inside the database container, so it works from any shell, including Windows PowerShell, with no local `psql` or `bash`. On a local install, run `bash scripts/demo.sh` instead.

Seven steps, each printing real database output: the duplicate cluster, vector similarity finding it, automatic routing, the merge transaction, SLA escalation, the constraints refusing bad data, and the trigger-written audit trail. Press Enter to advance, or set `NOPAUSE=1` to run straight through.

**Routing on filing.** In this demonstration build, a complaint filed through the web interface is embedded immediately with the SQL demo embedding, which fires the routing trigger, so the citizen sees the department straight away. This is controlled by `DEMO_EMBEDDINGS` (on by default in `docker-compose.yml`). With it set to `false`, complaints wait for the pipeline as they would in production: run `scripts/embed.py` for the real model, or the SQL-only equivalent:

```bash
docker compose exec db psql -U aegis -d aegis -f /aegis-scripts/embed_demo.sql
```

**Suggested five-minute demonstration**

1. Sign in as a citizen and file a pothole complaint worded differently from the existing ones.
2. Point out the confirmation: the complaint already has a department, and no dropdown was involved.
3. Sign in as staff, select the new complaint in the queue, and show the similarity percentage against the earlier report under "Is this a repeat of an earlier report?".
4. Choose **Join to this one**, confirm, and show the earlier grievance's Reports count go up.
5. Sign back in as the first citizen and show that their complaint now tracks the parent issue instead of disappearing.
6. Sign in as admin and show the dashboard, the overdue complaints in red, and the most-duplicated issues.

---

## 📸 Screenshots

Captured from a running instance by [`scripts/screenshots.mjs`](scripts/screenshots.mjs), which drives a real browser through the whole demo flow.

| Duplicate detection | Merged complaint still tracked |
|---|---|
| ![Duplicate detection](docs/screenshots/06-staff-duplicates.png) | ![Citizen view of a merged complaint](docs/screenshots/04-citizen-merged.png) |
| **Cross-department queue, breached SLAs in red** | **Admin dashboard** |
| ![Admin queue](docs/screenshots/09-admin-all-queue.png) | ![Admin dashboard](docs/screenshots/08-admin-dashboard.png) |

All nine screenshots are in [`docs/screenshots/`](docs/screenshots). To regenerate them:

```bash
npm install playwright && npx playwright install chromium
BASE=http://localhost:3000 node scripts/screenshots.mjs
```

---

## 🧠 Embeddings: demo vs real model

The seed data ships with embeddings from `fn_demo_embedding`, a **pure-SQL fallback** defined in `db/03_seed.sql`. It uses the hashing trick (each word hashed into one of 384 buckets, then L2-normalised), so the whole system can be demonstrated with nothing but `psql`.

To use the **real model**:

```bash
pip install -r scripts/requirements.txt
export DATABASE_URL=postgresql://user:pass@localhost:5432/aegis
python3 scripts/embed.py --recompute
```

This replaces every embedding with one from `sentence-transformers/all-MiniLM-L6-v2`. Duplicate detection and routing both improve noticeably, because the model encodes *meaning* rather than shared spelling.

| | Demo embedding | Real model |
|---|---|---|
| Needs Python | No | Yes |
| Matches on | Shared words | Meaning |
| Routing accuracy on seed data | 8 / 10 | Re-measure after recompute |

---

## 🔌 API reference

All routes are Next.js route handlers under `app/app/api/`. Every route other than login requires a valid session, and role checks are enforced server-side.

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/auth/login` | Sign in, sets signed `httpOnly` cookie |
| `POST` | `/api/auth/logout` | Invalidate the session |
| `GET` | `/api/complaints` | List complaints (scoped to the caller's role) |
| `POST` | `/api/complaints` | File a complaint (citizen) |
| `GET` | `/api/complaints/[id]` | Complaint detail |
| `PATCH` | `/api/complaints/[id]` | Update status (staff, own department only) |
| `GET` | `/api/complaints/[id]/duplicates` | Find duplicate candidates (staff) |
| `POST` | `/api/complaints/[id]/duplicates` | Merge a duplicate into a parent (staff) |
| `GET` | `/api/search` | Full-text search |
| `GET` | `/api/dashboard` | Per-department statistics (admin only) |
| `GET` | `/api/auth/me` | Who is signed in |
| `GET` | `/api/public/stats` | Headline counts for the landing page; no sign-in, no personal data |
| `POST` | `/api/admin/escalate` | Run the SLA sweep now (admin only) |

---

## ✅ Testing

| Suite | Command | Result |
|---|---|---|
| **Database tests**: constraints, triggers, rollback, search, views, SLA, cascades, CTEs/windows | `bash scripts/run_tests.sh` | **33 / 33** |
| **Concurrency test**: two sessions race to merge the same complaint | `bash scripts/concurrency_test.sh` | **PASS** |
| **API tests**: auth, role-based access, both workflows, search, logout, interface endpoints | see below | **36 / 36** |
| **Consistency audit**: docs, diagrams, Docker setup and screenshots vs the live schema | `python3 scripts/audit.py` | **92 / 92** |

`run_tests.sh` creates a throwaway database, runs all six SQL files, and reports PASS/FAIL per check.

**API tests** need the app running:

```bash
cd app && npm run build && npm start &
BASE=http://localhost:3000 bash scripts/api_test.sh
```

**Highlights of what the tests prove**

- Wrong password and unknown account return the *same* 401, so account existence cannot be probed.
- A tampered session cookie is rejected by the HMAC check.
- A failed merge **rolls back completely**, leaving no stray link and an unchanged counter.
- In the concurrency race, session B blocks on A's lock, re-reads the row after A commits, and is rejected by validation. Exactly one merge takes effect.
- `npm audit` on the production dependency tree reports **0 vulnerabilities**.

---

## 📁 Repository layout

```
aegis-project/
├── docker-compose.yml             db (pgvector) + app, healthcheck, auto-seeding
├── .env.example                   Docker Compose configuration template
├── .gitattributes                 forces LF so scripts run inside Linux containers
├── db/
│   ├── 01_schema.sql              tables, types, constraints, indexes, views
│   ├── 02_functions.sql           stored functions and triggers
│   ├── 03_seed.sql                sample data + SQL-only demo embedder
│   ├── 04_queries.sql             15 report queries used by the app and write-up
│   ├── 05_test.sql                33 database tests
│   └── 06_advanced_queries.sql    CTEs, window functions, recursive queries, FTS
├── app/                           Next.js application
│   ├── Dockerfile                 multi-stage build, non-root runtime
│   ├── lib/
│   │   ├── db.js                  connection pool, parameterised query helper
│   │   └── auth.js                bcrypt login, HMAC session cookie, role guard
│   └── app/
│       ├── api/                   route handlers
│       ├── citizen/  staff/  admin/   role-specific pages
│       └── page.jsx               login
├── scripts/
│   ├── demo.sh                    guided 7-step demonstration
│   ├── embed.py                   embedding pipeline (all-MiniLM-L6-v2)
│   ├── embed_demo.sql             SQL-only embedding pipeline for demos
│   ├── screenshots.mjs            Playwright capture of the demo flow
│   ├── run_tests.sh               database test runner
│   ├── api_test.sh                end-to-end API test runner
│   ├── concurrency_test.sh        two-session merge race
│   └── audit.py                   docs/diagrams vs the live schema
├── docs/
│   ├── AEGIS_Project_Documentation.md   full project write-up
│   ├── AEGIS_Submission_Report.md       9-section submission report
│   ├── normalization.md                 FDs and 1NF–BCNF analysis
│   └── screenshots/                     9 captured screenshots
└── diagrams/
    ├── aegis_erd_chen.*                 ER diagram (Chen notation)
    └── aegis_relational_schema.*        relational schema with FK arrows
```

---

## 🧭 Design decisions worth knowing

These are easy to miss when reading the code.

**Business rules live in the database.** The audit trail is a trigger, not application code, so it fires whether the write came from the app, a stored function, or a manual `psql` session. The merge is a stored function, so its three steps are atomic no matter who calls it.

**The SLA deadline is stored, not computed.** It is a snapshot taken at filing time. Deriving it from the department's current policy would silently rewrite the deadline of every historical complaint whenever that policy changed. This is also why `complaint` stays in BCNF.

**Duplicate search is restricted to the same ward.** Two potholes in different parts of the city are not the same pothole, however similar the wording. This one filter stops the feature from being actively harmful.

**Routing weights neighbours by the square of their similarity.** A plain head-count let a department that merely appears more often in the archive outvote the single obvious match. Squaring made one close neighbour decisive and lifted accuracy from 6/10 to 8/10 on the seed data.

**Locking, not just constraints.** A `UNIQUE` key would stop the second `INSERT` of a racing merge, but only after both sessions had read stale state. `SELECT … FOR UPDATE` makes the read-then-write sequence atomic, with consistent lock ordering (child before parent) to prevent deadlock.

**The embedding lives in its own table.** The vector arrives asynchronously, after the complaint row exists, and at roughly 1.5 KB it would bloat ordinary complaint reads.

---

## 🔮 Future work

1. **Photo embeddings.** CLIP image vectors alongside text, to catch duplicates described differently but photographed identically.
2. **Geographic clustering.** Use the stored latitude and longitude with PostGIS and a radius filter, which is finer than the ward filter.
3. **Routing confidence.** Return a confidence score so only confident routings are automatic and the rest go to human triage.
4. **Feedback loop.** Treat staff overrides of routing as training signal.
5. **Partition `status_history`.** Range-partition the audit trail by month as it grows.

---

## 📚 Documentation

| Document | Contents |
|---|---|
| [`docs/AEGIS_Project_Documentation.md`](docs/AEGIS_Project_Documentation.md) | Problem statement, objectives, scope, data dictionary, vector implementation, concurrency analysis, test results, requirement coverage |
| [`docs/AEGIS_Submission_Report.md`](docs/AEGIS_Submission_Report.md) | The 9-section submission report: abstract, stack, SQL and vector commands, project tree, screenshots, rubric status |
| [`docs/normalization.md`](docs/normalization.md) | Functional dependencies for every relation and the path to BCNF |
| [`diagrams/`](diagrams) | ER diagram and relational schema (PNG and editable `.drawio`) |

---

<div align="center">

**Built by Siddanth Anil (`PES1UG24AM274`) and Shubham Bhat (`PES1UG24AM273`)**
PES University · DBMS Level 3 Project

</div>
