# AEGIS — Civic Grievance Routing and Duplicate Detection System

**DBMS Experiential Learning — Level 3 Project**
PES University · Course instructor: Dr. Nagasundari S

---

## 1. Problem statement

Municipal grievance portals in Indian cities suffer from two problems that have nothing to do with how hard the staff work.

**The same issue is reported many times.** When a pothole opens on a busy road, dozens of people report it over the following week. Each report becomes a separate ticket. Staff then spend their time reading near-identical complaints and closing them one by one, and the citizen who reported it first has no idea that thirty neighbours reported the same thing.

**Complaints reach the wrong department.** Portals typically ask the citizen to pick a category from a dropdown. Citizens pick wrong, because they are describing a problem, not filing a work order. A misfiled complaint sits in one department's queue until somebody notices and forwards it, and the clock has been running the whole time.

Both problems have the same root cause: the complaint itself is **unstructured text**, and a conventional database can only match it on exact keywords.

AEGIS addresses both. It converts every complaint description into a vector embedding and uses similarity search to (a) detect near-duplicate reports so they can be merged into one tracked issue, and (b) route a new complaint to the department that resolved the most similar past complaints.

---

## 2. Objectives

1. Detect near-duplicate complaints automatically, even when they share no keywords, and let staff merge them into a single tracked issue without losing the individual reporters.
2. Route complaints to a department by learning from resolution history rather than from a dropdown the citizen has to guess at.
3. Track an SLA deadline per complaint and escalate automatically when it passes.
4. Give citizens an honest view of their complaint, including the status of the parent issue when their report was merged into one.
5. Give administrators a view of department performance: resolution times, breach rates and which issues are being reported repeatedly.
6. Enforce data integrity in the database itself, so the rules hold no matter which client writes to it.

---

## 3. Scope

**In scope**

- Citizen registration, login, complaint filing and tracking
- Staff work queue sorted by SLA urgency, status updates, duplicate review and merging
- Admin dashboard with per-department statistics
- Automatic routing driven by vector similarity over resolution history
- Automatic SLA escalation
- Full-text keyword search across complaints
- Role-based access control with three effective roles (Citizen, Staff, Admin)

**Out of scope**

- Mobile applications; the web interface is responsive but there is no native app
- Payment or fine collection
- Integration with real BBMP or government systems; the dataset is synthetic
- Live GPS capture; latitude and longitude are stored but entered manually
- Multi-language complaint text; embeddings are generated for English

---

## 4. Functional requirements

| # | Requirement | Where it is implemented |
|---|---|---|
| FR1 | A citizen can register and sign in | `citizen` table, `/api/auth/login` |
| FR2 | A citizen can file a complaint with title, description, priority and optional location | `fn_file_complaint`, `POST /api/complaints` |
| FR3 | A citizen can see only their own complaints | `v_citizen_complaints`, server-side filter in `GET /api/complaints` |
| FR4 | A citizen whose complaint was merged can see the parent complaint's progress | `v_citizen_complaints` |
| FR5 | The system assigns a department automatically | `fn_route_complaint`, trigger `t_embedding_auto_route` |
| FR6 | Every complaint gets an SLA deadline when filed | `fn_file_complaint`, `ck_complaint_sla` |
| FR7 | Overdue complaints are escalated automatically | `fn_escalate_overdue` |
| FR8 | Staff can see their department's queue, most urgent first | `v_open_queue`, `GET /api/complaints` |
| FR9 | Staff can see likely duplicates of a complaint with a similarity score | `fn_find_duplicates`, `GET /api/complaints/[id]/duplicates` |
| FR10 | Staff can merge a duplicate into a parent complaint | `fn_merge_duplicate`, `POST /api/complaints/[id]/duplicates` |
| FR11 | Staff can change a complaint's status | `PATCH /api/complaints/[id]` |
| FR12 | Every status change is recorded in an audit trail | Trigger `t_complaint_status_audit` |
| FR13 | Admins can see per-department performance statistics | `mv_department_performance`, `GET /api/dashboard` |
| FR14 | Any signed-in user can search complaints by keyword | `search_tsv` + GIN index, `GET /api/search` |
| FR15 | Citizens cannot perform staff actions, and staff cannot act outside their department | `requireRole`, department filter in SQL |

---

## 5. ER diagram

The conceptual design is in Chen notation, in `diagrams/aegis_erd_chen.png` (editable source: `diagrams/aegis_erd_chen.drawio`).

**Entities (9).** Four strong entities that exist independently — `WARD`, `CITIZEN`, `DEPARTMENT`, `STAFF` — plus `COMPLAINT` at the centre, and three weak entities that cannot exist without a complaint: `COMPLAINT_EMBEDDING`, `STATUS_HISTORY` and `FEEDBACK`.

**Relationships (10).** `EMPLOYS`, `RESIDES_IN`, `ROUTED_TO`, `ASSIGNED_TO`, `FILES`, `LOCATED_IN`, the recursive `MERGED_INTO`, and three identifying relationships (`VECTORISED_AS`, `TRACKED_BY`, `RECEIVES`) that attach the weak entities to `COMPLAINT`.

**Notation features used.** Strong and weak entities, identifying relationships (double diamonds), primary keys (underlined), partial keys (italic underlined), multivalued attributes (`phone`, `attachment_url` — double ovals), a derived attribute (`duplicate_count` — dashed oval, because it can be recomputed by counting `MERGED_INTO`), a composite attribute (`geo_location` decomposing into `latitude` and `longitude`), total participation (double lines) and a recursive relationship with role labels.

**Two modelling decisions worth noting.**

*Why `MERGED_INTO` is a relationship, not an entity.* Linking a duplicate to its parent is a relationship between two complaints. It carries its own attributes — the similarity score and the merge timestamp — which is exactly the case where a relationship needs attributes of its own. It becomes a table only during the relational mapping, because SQL has no other way to store a relationship with attributes.

*Why the three weak entities are weak.* None of them has an identity independent of a complaint. A status-history row is meaningless on its own; it is identified by *when* it happened *within* a particular complaint, which is what a partial key means.

---

## 6. Relational schema

The mapped schema is in `diagrams/aegis_relational_schema.png` (editable source: `.drawio`), drawn in the Elmasri–Navathe style with an arrow from each foreign key to the primary key it references.

**11 tables**, two more than the nine ER entities. The extra two come from the standard mapping rules:

| ER construct | Mapping rule applied | Result |
|---|---|---|
| 1:N relationships (`ROUTED_TO`, `ASSIGNED_TO`, `FILES`, `LOCATED_IN`, `EMPLOYS`, `RESIDES_IN`) | Foreign key on the N side | FK columns, no new tables |
| Multivalued attribute `phone` | New relation keyed by owner PK + the attribute | `citizen_phone` |
| Multivalued attribute `attachment_url` | Same rule | `complaint_attachment` |
| Recursive relationship with attributes `MERGED_INTO` | New relation with two FKs to the same table | `duplicate_link` |
| Weak entity `STATUS_HISTORY` | Owner PK + partial key becomes composite PK | `status_history (complaint_id, changed_at)` |
| Weak entities `COMPLAINT_EMBEDDING`, `FEEDBACK` (both 1:1) | Owner PK alone is sufficient as PK | PK = FK = `complaint_id` |
| Composite attribute `geo_location` | Flattened to its leaf attributes | `latitude`, `longitude` |

Making the foreign key *also* the primary key in `complaint_embedding` and `feedback` is what enforces the one-to-one: a complaint can have at most one embedding and at most one feedback row, and the database guarantees it.

### 6.1 Normalization

**All 11 relations are in BCNF.** The full functional-dependency analysis — every relation's FDs, its candidate keys, and why it reaches BCNF — is in [`docs/normalization.md`](normalization.md).

The three points most likely to be probed:

- **`status_history` is the only relation where the 2NF check is non-vacuous**, because it is the only one with a composite key `(complaint_id, changed_at)` and non-prime attributes. Neither half of the key determines anything alone, so there is no partial dependency.
- **`citizen_phone` and `complaint_attachment` exist because of 1NF.** Storing several phone numbers in one column would not be atomic; adding `phone1`, `phone2`, `phone3` would be a repeating group. Both fail 1NF, which is exactly why the ER-to-relational rule for multivalued attributes produces a separate relation.
- **`sla_deadline` is not transitively dependent on `dept_id`.** If it were computed from the department's current SLA policy, `(dept_id, filed_at) → sla_deadline` would hold and the relation would fall out of BCNF. It is a snapshot stored at filing time, so it is independent data. The business rule and the normal form point the same way here.

`complaint.duplicate_count` is a deliberate denormalization. It is **not** a normal-form violation — it is determined by the key — but it does duplicate a fact held in `duplicate_link`. Section 5 of the normalization document explains why that is acceptable and the four checks that keep it honest.

The diagram is checked against the live database by `scripts/audit.py` (group H), which compares every table, column and primary key. The only deliberate difference is `complaint.search_tsv`, a generated full-text index column that belongs to the physical schema rather than the conceptual mapping.

---

## 7. Database choice and justification

The project specification requires at least two database paradigms and asks for the choice to be justified by the nature of the data, not by technology demonstration. AEGIS uses **PostgreSQL 16 + pgvector** (Option 2: SQL + vector database).

### Why SQL for the structured half

Complaints, citizens, staff, departments, wards, status history and merge links are all **discrete entities with hard rules between them**:

- A complaint must belong to exactly one citizen and one ward.
- A staff member belongs to exactly one department.
- A merge must reference two complaints that actually exist, and they must be different complaints.
- A complaint marked `RESOLVED` must carry a resolution timestamp.

These are referential integrity and constraint problems — precisely what a relational database is built for. In a document store each of these rules would have to be re-implemented in application code and would hold only as long as every client remembered to apply it. In PostgreSQL they are declared once as `FOREIGN KEY` and `CHECK` constraints and hold against every client, including a manual `psql` session.

The merge operation is also a three-step change (write the link, mark the child merged, increment the parent counter) that must happen completely or not at all. That is a transaction, and it is the relational model's core guarantee.

### Why a vector database for the unstructured half

The complaint *description* is free text, and the two central questions the system asks about it are:

- "Is this the same issue as something already reported?"
- "Which department handles problems that look like this one?"

Neither is a keyword question. *"Huge pothole near the bus stop"* and *"Dangerous crater on main road"* describe the same pothole and share almost no words. A `LIKE` query or even full-text search scores them as unrelated. Embedding both into a 384-dimension vector space places them close together, because the model encodes meaning rather than spelling.

The description has no useful relational decomposition — splitting it into columns would destroy the thing we need to compare. So it is stored as a vector and compared with cosine distance.

### Why pgvector specifically, rather than a separate vector service

Using pgvector keeps both halves in one database, which means a single query can join structured filters to a similarity search:

```sql
WHERE c.ward_id = $1          -- structured: same ward
  AND c.status <> 'MERGED'    -- structured: not itself a duplicate
  AND (1 - (e.embedding <=> $2)) >= 0.80   -- vector: similar text
```

That ward filter matters: two potholes in different parts of the city are not the same pothole however similar the wording is. With a separate vector service (Pinecone, Qdrant) this query becomes two round trips plus a merge in application code, and the combined result can no longer be made transactional with the merge operation. Keeping everything in PostgreSQL avoids a second system to deploy and keep consistent.

---

## 8. Data dictionary

11 base tables, 19 `CHECK` constraints, 15 foreign keys, 23 indexes, 2 views, 1 materialized view, 3 triggers and 6 stored functions.

#### `citizen`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `citizen_id` | integer | no | Primary key / FK to citizen |
| `email` | character varying(120) | no | Login identifier, unique |
| `full_name` | character varying(120) | no | Display name |
| `password_hash` | character varying(255) | no | bcrypt hash of the password |
| `ward_id` | integer | no | FK to ward |
| `created_at` | timestamp with time zone | no | Account creation time |

#### `citizen_phone`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `citizen_id` | integer | no | Primary key / FK to citizen |
| `phone` | character varying(15) | no | One phone number (part of composite PK) |

#### `complaint`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `complaint_id` | integer | no | Primary key / FK to complaint |
| `citizen_id` | integer | no | Primary key / FK to citizen |
| `dept_id` | integer | yes | Primary key / FK to department |
| `ward_id` | integer | no | FK to ward |
| `assigned_staff_id` | integer | yes | FK to staff, NULL until triaged |
| `title` | character varying(150) | no | Short summary typed by the citizen |
| `description` | text | no | Full text of the complaint |
| `status` | complaint_status | no | Lifecycle state |
| `priority` | complaint_priority | no | Urgency reported by the citizen |
| `latitude` | numeric | yes | Location, paired with longitude |
| `longitude` | numeric | yes | Location, paired with latitude |
| `filed_at` | timestamp with time zone | no | When the complaint was submitted |
| `sla_deadline` | timestamp with time zone | no | Snapshot deadline taken at filing time |
| `resolved_at` | timestamp with time zone | yes | When it was closed |
| `duplicate_count` | integer | no | How many duplicates were merged in |
| `search_tsv` | tsvector | yes | Generated full-text index column |

#### `complaint_attachment`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `complaint_id` | integer | no | Primary key / FK to complaint |
| `attachment_url` | character varying(500) | no | One photo or document URL |

#### `complaint_embedding`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `complaint_id` | integer | no | Primary key / FK to complaint |
| `embedding` | ARRAY | no | 384-dimension vector of the description |
| `model_name` | character varying(60) | no | Which embedding model produced the vector |
| `generated_at` | timestamp with time zone | no | When the embedding was created |

#### `department`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `dept_id` | integer | no | Primary key / FK to department |
| `dept_name` | character varying(80) | no | Department name |
| `category` | character varying(60) | no | Broad service category |
| `default_sla_hours` | integer | no | Hours allowed to resolve, by policy |

#### `duplicate_link`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `child_complaint_id` | integer | no | The duplicate (primary key) |
| `parent_complaint_id` | integer | no | The complaint it was merged into |
| `similarity_score` | real | no | Cosine similarity that justified the merge |
| `merged_by` | integer | yes | Staff member who approved the merge |
| `merged_at` | timestamp with time zone | no | When the merge happened |

#### `feedback`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `complaint_id` | integer | no | Primary key / FK to complaint |
| `submitted_at` | timestamp with time zone | no | When feedback was left |
| `rating` | smallint | no | 1 to 5 |
| `comments` | text | yes | Free-text feedback |

#### `staff`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `staff_id` | integer | no | Primary key / FK to staff |
| `email` | character varying(120) | no | Login identifier, unique |
| `full_name` | character varying(120) | no | Display name |
| `password_hash` | character varying(255) | no | bcrypt hash of the password |
| `role` | staff_role | no | STAFF or ADMIN |
| `dept_id` | integer | no | Primary key / FK to department |

#### `status_history`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `complaint_id` | integer | no | Primary key / FK to complaint |
| `changed_at` | timestamp with time zone | no | Timestamp (partial key) |
| `old_status` | complaint_status | yes | State before the change |
| `new_status` | complaint_status | no | State after the change |
| `changed_by` | integer | yes | Staff member, NULL if a trigger did it |
| `remarks` | text | yes | Free-text note |

#### `ward`

| Column | Type | Null | Purpose |
|---|---|---|---|
| `ward_id` | integer | no | Primary key |
| `ward_name` | character varying(80) | no | Name of the ward |
| `zone` | character varying(40) | no | Broad city zone (North/South/East/West) |

### Enumerated types

| Type | Values | Used by |
|---|---|---|
| `complaint_status` | `OPEN`, `ROUTED`, `IN_PROGRESS`, `RESOLVED`, `MERGED`, `ESCALATED` | `complaint.status`, `status_history.old_status`, `status_history.new_status` |
| `complaint_priority` | `LOW`, `MEDIUM`, `HIGH`, `CRITICAL` | `complaint.priority` |
| `staff_role` | `STAFF`, `ADMIN` | `staff.role` |

These are defined as types rather than repeated `CHECK` constraints because the value set is closed, small, and shared by more than one table.

---

## 9. SQL and vector database implementation

### 9.1 DDL (`db/01_schema.sql`)

| Feature | Where |
|---|---|
| `CREATE TABLE` | 11 tables |
| `CREATE TYPE` | 3 enumerated types |
| `ALTER TABLE` | 3 changes: add `duplicate_count` with its CHECK, add the generated `search_tsv` column, widen `department.category` |
| `DROP` | All objects dropped at the top so the script is re-runnable |
| Primary keys | Including three composite PKs: `citizen_phone`, `complaint_attachment`, `status_history` |
| Foreign keys | 15, each with a deliberate `ON DELETE` action (see below) |
| Constraints | 19 `CHECK` plus `UNIQUE` on every natural key |
| Indexes | 23 total, including one HNSW, one GIN, and two partial indexes |
| Views | 2 views and 1 materialized view |

**`ON DELETE` actions are chosen per relationship, not copy-pasted.**

- `RESTRICT` on `ward` and `department` — you must not be able to orphan a complaint's geography or lose its routing history by deleting a reference row.
- `SET NULL` on `assigned_staff_id` and `merged_by` — a staff member leaving should not destroy their complaints; the work returns to the unassigned pool.
- `CASCADE` only where the child row is meaningless without its parent: embeddings, attachments, status history and feedback.

### 9.2 Advanced database features

The specification asks for at least four. AEGIS implements **six**.

| # | Feature | Implementation |
|---|---|---|
| 1 | **Transactions** | `fn_merge_duplicate` performs the three-step merge atomically, with `SELECT ... FOR UPDATE` row locks so two staff members cannot merge the same pair concurrently. Test T3.5 proves a failed merge rolls back completely. |
| 2 | **Views** | `v_open_queue` (staff queue with computed hours-remaining and breach flag), `v_citizen_complaints` (citizen view that follows merge links to the parent), and the materialized `mv_department_performance`. |
| 3 | **Stored functions** | `fn_find_duplicates`, `fn_route_complaint`, `fn_merge_duplicate`, `fn_file_complaint`, `fn_escalate_overdue`. |
| 4 | **Triggers** | `t_complaint_status_audit` (writes the audit trail), `t_complaint_validate` (blocks illegal transitions, stamps `resolved_at`), `t_embedding_auto_route` (routes a complaint when its embedding arrives). |
| 5 | **Indexing** | B-tree, composite, GIN, HNSW and two partial indexes. |
| 6 | **Full-text search** | Generated `tsvector` column with weighted title and description, GIN-indexed, queried with `websearch_to_tsquery`. |
| 7 | **Vector similarity search** | pgvector `VECTOR(384)` with HNSW and cosine distance. |

**Why the audit trail is a trigger and not application code.** A trigger fires regardless of who writes — the web app, a stored function, or a manual `UPDATE` in `psql`. Putting it in application code would mean the audit trail is complete only as long as every future code path remembers to write it.

**Why the SLA deadline is stored, not computed.** `sla_deadline` is a snapshot taken when the complaint is filed. If it were derived from `department.default_sla_hours` at read time, changing a department's SLA policy would silently move the deadline of every historical complaint and make past breach statistics wrong.

**Why `duplicate_count` is denormalised.** It could be computed by counting `duplicate_link` rows. It is stored and maintained by the merge function so that rendering the staff queue does not require a correlated `COUNT(*)` per row. This is a deliberate trade of a small write cost for a large read saving, and test T3.2 verifies the stored counter matches the real link count.

### 9.3 Vector implementation details

The specification asks five specific questions about the vector component.

**What data is converted into embeddings.** The complaint's `title` concatenated with its `description` — everything the citizen typed. Structured fields (ward, priority, timestamps) are deliberately excluded; they are already queryable in SQL and including them would dilute the semantic signal.

**Which embedding model.** `sentence-transformers/all-MiniLM-L6-v2`, producing 384 dimensions. It was chosen because it is trained specifically for sentence similarity (not for classification or generation), runs comfortably on CPU, and 384 dimensions is small enough that the index stays fast on a dataset this size.

**How vectors are stored.** In a dedicated `complaint_embedding` table as a `VECTOR(384)` column, indexed with HNSW using `vector_cosine_ops`. The table is separate from `complaint` for two reasons: the embedding is produced asynchronously, after the complaint row exists; and a 384-float vector is roughly 1.5 KB, so keeping it out of the main table means ordinary complaint queries do not read it.

**Similarity metric.** Cosine distance, via pgvector's `<=>` operator. The model emits L2-normalised vectors, so cosine is the metric it was trained under, and similarity is simply `1 - distance`.

**How relevant results are retrieved.** `fn_find_duplicates` fetches the subject complaint's embedding, then runs a nearest-neighbour search restricted to complaints in the **same ward**, filed **earlier**, and **not already merged**, keeping only those above a similarity threshold (default 0.80). The ward restriction is the important one: it is what stops the system from merging two genuinely different potholes in different parts of the city.

**Running the pipeline without the model.** `db/03_seed.sql` defines `fn_demo_embedding`, a pure-SQL fallback that embeds text with the classic hashing trick (each word hashed into one of 384 buckets, then L2-normalised). It is a real, if simple, text embedding, and it lets the whole system be demonstrated with nothing but `psql`. Its accuracy is lower than the real model — see section 13 for measured numbers.

### 9.4 Transactions, concurrency control and locking

The merge operation is the one place in AEGIS where two users can collide. Two staff members reviewing the same work queue can both decide that complaint #19 is a duplicate of #15 and click merge at the same moment.

Without protection this is a classic **lost update / double-apply race**. `fn_merge_duplicate` does three writes:

1. insert a row into `duplicate_link`
2. set the child's status to `MERGED`
3. increment the parent's `duplicate_count`

If both sessions interleave between steps, both could pass validation, and the parent's counter would end at 2 for a single real duplicate.

**How it is prevented.** Before doing anything, the function takes explicit row locks:

```sql
SELECT status INTO v_child_status
  FROM complaint WHERE complaint_id = p_child_id FOR UPDATE;
SELECT status INTO v_parent_status
  FROM complaint WHERE complaint_id = p_parent_id FOR UPDATE;
```

`SELECT ... FOR UPDATE` takes a row-level exclusive lock. The second session blocks on that lock until the first commits, and then — crucially — **re-reads** the row and sees `status = 'MERGED'`, so validation rejects it. The two transactions are forced into a serial order instead of interleaving.

A `UNIQUE` constraint alone would not be enough. The primary key on `duplicate_link.child_complaint_id` would stop the second `INSERT`, but only *after* both sessions had already read a stale status and begun work. The lock is what makes the read-then-write sequence atomic.

**Isolation level.** AEGIS runs at PostgreSQL's default, `READ COMMITTED`. At this level a statement sees only data committed before the statement began, so without the explicit lock the second session's `SELECT` would happily return the pre-merge status. Explicit `FOR UPDATE` locking is the standard way to get the needed guarantee at `READ COMMITTED` without paying for `SERIALIZABLE` across the whole application. Lock ordering is consistent (child before parent, always), which is what prevents deadlock between two merges running in opposite directions.

**Proof, not assertion.** `scripts/concurrency_test.sh` runs the race for real: session A merges and holds its transaction open for three seconds; session B attempts the identical merge one second later. Measured result:

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
  child status                : MERGED
PASS - the race was prevented; exactly one merge took effect.
```

Session B's error is the evidence: it did not fail on a constraint, it failed on the *validation check*, which means it had blocked on the lock and then re-read the row after A committed. That is serialization working.

**Atomicity.** A PL/pgSQL function runs inside a single transaction, so any `RAISE EXCEPTION` rolls back every change the function has already made. Test T3.5 forces a merge to fail after the `duplicate_link` insert and asserts that no stray link row remains and the parent counter is unchanged.

---

---

## 10. Important queries

All 15 are in `db/04_queries.sql` and run as a group. A selection:

**Q3 — departments slower than the overall average.** Demonstrates `GROUP BY` with `HAVING` filtering on an aggregate, where the threshold itself comes from a scalar subquery:

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

**Q4 — most-duplicated complaints.** The headline feature, as a report: `JOIN` + `GROUP BY` + `HAVING COUNT(...) >= 1` over `duplicate_link`.

**Q9 — vector similarity search.** `SELECT * FROM fn_find_duplicates(18, 0.30, 5);`

**Q12 — resolved complaints with no feedback.** A correlated `NOT EXISTS` subquery.

**Q15 — index usage proof.** `EXPLAIN` showing the partial index `idx_complaint_sla_open` being used by the SLA sweep.

Coverage across the file: `JOIN` (inner and left), `GROUP BY`, `HAVING`, `ORDER BY`, aggregate functions (`COUNT`, `AVG`, `SUM`), `FILTER`, scalar and correlated subqueries, `NOT EXISTS`, `string_agg`, full-text search and vector search.

### 10.1 CTEs, window functions and full-text search

A further ten queries are in `db/06_advanced_queries.sql`, covering the Unit 2 topics that the application queries above do not reach.

| # | Technique | What it answers |
|---|---|---|
| W1 | `RANK() OVER (PARTITION BY ...)` | Urgency ranking that restarts at 1 inside each department |
| W2 | Window aggregate without collapsing rows | Each complaint beside its own department's average |
| W3 | `SUM/COUNT OVER (... ORDER BY ...)`, `ROW_NUMBER()` | Running total of complaints per ward over time |
| W4 | `LAG()` | Hours since the previous complaint in the same ward |
| W5 | CTE + `DENSE_RANK()` | Top 2 slowest complaints per department |
| W6 | Three CTEs joined | Ward scorecard: filed, resolved, merged, duplicate rate |
| W7 | `WITH RECURSIVE` | Walk a merge chain from a duplicate up to the canonical complaint |
| W8 | `WITH RECURSIVE` | Deepest merge chain in the whole table — an integrity check |
| W9 | `ts_headline`, `ts_rank` | Search results with the matching fragment highlighted |
| W10 | CTE + `NTILE(4)` + window `SUM` | Department scorecard with speed quartiles |

Two of these are worth drawing attention to in a demonstration.

**W5 needs two steps for a reason.** A window function cannot appear in a `WHERE` clause, because window functions are evaluated after `WHERE`. The ranking therefore has to be computed in a CTE and filtered in the outer query. This is the standard "top N per group" pattern and the usual reason a CTE is unavoidable rather than merely tidy.

**W8 is a test disguised as a query.** `fn_merge_duplicate` refuses to merge into an already-merged complaint, so merge chains should never exceed one hop. The recursive CTE measures the actual maximum depth across the whole table; it returns 1. If it ever returned more, the rule would have leaked somewhere. This is asserted as test T7.2.

---

## 11. System architecture

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
                        │  DATABASE_URL (from .env.local)
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

**Layering principle.** Business rules live in the database, not the web layer. The web layer authenticates the user, decides what they are allowed to ask for, and calls a stored function. This means the rules survive a second client being written against the same database — and it is also why the test suite can verify them with `psql` alone.

**Why the embedding pipeline is separate.** Generating an embedding takes tens of milliseconds and needs a Python model that has no place inside a web request. Running it as a separate process means filing a complaint stays fast, and the complaint simply waits (as `OPEN`, unrouted) until its embedding arrives. The auto-routing trigger then fires as a consequence of the insert.

---

## 12. Application screenshots

Screenshots must be captured from your own running instance and placed in `docs/screenshots/`. Capture at least these five, which together cover every requirement a demonstrator will look for:

| File | Page | What it should show |
|---|---|---|
| `01-login.png` | `/` | The sign-in form with the Citizen / Staff selector |
| `02-citizen-file.png` | `/citizen` | A complaint being filed, and the complaint list beside it |
| `03-citizen-merged.png` | `/citizen` | A complaint showing "Same issue as #15 … now RESOLVED" — proof that a merged complaint still tracks |
| `04-staff-duplicates.png` | `/staff` | The work queue with an overdue row in red, and the duplicate panel open showing similarity percentages |
| `05-admin-dashboard.png` | `/admin` | Department performance table and the most-duplicated issues table |

To reproduce the state in screenshot 3 and 4, run the seed script — complaints 16, 17 and 18 are pre-merged into 15, and complaints 23 and 24 are already past their SLA deadline.

---

## 13. Testing results

Two automated suites. Both are checked in and runnable.

### 13.1 Database tests — `db/05_test.sql`

**33 of 33 passed**, executed against PostgreSQL 16.

| Group | Tests | Result | What it proves |
|---|---|---|---|
| 1. Constraints | 7 | 7 pass | `UNIQUE`, `CHECK`, `FOREIGN KEY` and `ON DELETE RESTRICT` all reject bad data |
| 2. Triggers | 6 | 6 pass | Audit rows written automatically; `resolved_at` stamped; closed complaints cannot be reopened; `IN_PROGRESS` requires an assignee; auto-routing assigned a department to 10 of 10 complaints |
| 3. Transactions | 5 | 5 pass | Three merges landed; the denormalised counter matches the real link count; self-merge and merge-into-merged are refused; **a failed merge rolls back completely, leaving no stray link and an unchanged counter** |
| 4. Search | 4 | 4 pass | Similarity search returns the right cluster (top candidate for #18 is #15 at 0.588); an unrelated complaint returns nothing at a high threshold; full-text search returns 4 matches for "pothole" |
| 5. Views & SLA | 5 | 5 pass | The open queue leaks no closed complaints; the citizen view resolves merge links; the SLA sweep escalated exactly the 2 overdue complaints and is idempotent on a second run |
| 6. Cascades | 1 | 1 pass | Deleting a complaint leaves no orphaned embedding, attachment or history row |
| 7. CTEs & windows | 5 | 5 pass | The recursive CTE walks the merge chain correctly; no chain exceeds one hop; `RANK()` restarts at 1 in every partition; window counts agree with `GROUP BY` counts; `ts_headline` highlights matches |

Note that the negative tests are the important ones. Seven of these tests pass *because the database refused to do something*, which is the only way to demonstrate that a constraint is actually enforced rather than merely declared.

### 13.1b Concurrency test — `scripts/concurrency_test.sh`

**PASS.** Two sessions attempt the identical merge with overlapping transactions. Session B blocks on session A's `FOR UPDATE` lock, then re-reads after A commits and is rejected by validation. Exactly one `duplicate_link` row is created and the parent counter increments by exactly one. Full output and analysis in §9.4.

### 13.2 API tests — `scripts/api_test.sh`

**36 of 36 passed**, against a production build of the app on a seeded database.

| Group | Tests | Result | What it proves |
|---|---|---|---|
| A. Authentication | 7 | 7 pass | Unauthenticated requests refused; wrong password and unknown account return the *same* 401 so account existence cannot be probed; a tampered session cookie is rejected by the HMAC check |
| B. Authorisation | 6 | 6 pass | Citizens get 403 on the admin dashboard, the duplicate search and status updates; ordinary staff also get 403 on the admin dashboard; staff cannot file complaints |
| C. Citizen workflow | 5 | 5 pass | A citizen can list and file; reading another citizen's complaint returns 404; short title and short description are both rejected with 400 |
| D. Staff workflow | 6 | 6 pass | Queue loads; duplicate search returns candidates; self-merge and merge-into-merged return 409 from the stored function; a staff member gets 404 updating another department's complaint; an invalid status value is rejected |
| E. Search | 3 | 3 pass | Full-text search returns matches and requires a session |
| F. Logout | 2 | 2 pass | The session is invalid immediately after logout |
| G. Interface endpoints | 7 | 7 pass | Public figures need no sign-in and contain no names or complaint text; the SLA sweep refuses signed-out users (401) and ordinary staff (403); a new complaint is routed to a department as soon as it is filed |

### 13.3 Routing accuracy

Measured on the 10 seeded live complaints using the **demo** (`fn_demo_embedding`) vectors:

**8 of 10 routed to the correct department.** The two misses are complaint 23 (footpath repair → Parks instead of Roads, arguable either way since the only historical footpath complaint was handled by Parks) and complaint 24 (fallen tree branch → Water Supply, a clear miss).

This is the demo embedding's ceiling, not the system's. The hashing trick matches on shared *words*; with only 14 historical complaints to learn from, a complaint whose vocabulary does not overlap any of them has nothing to match. The real `all-MiniLM-L6-v2` model encodes meaning rather than spelling and does substantially better on exactly these cases. **If you demonstrate with the real model, re-measure this number and report what you actually get** rather than quoting this one.

The routing function itself weights each neighbour by the **square** of its similarity rather than counting votes. A plain head-count let a department that merely appears more often in the archive outvote the one department whose complaint was an obvious match; squaring makes one close neighbour decisive. That change alone took accuracy from 6/10 to 8/10 on this dataset.

### 13.4 Dependency security

`npm audit` on the production dependency tree reports **0 vulnerabilities**. The project pins Next.js 16.4.3; the entire Next 14 line carries unpatched advisories including unauthenticated remote code execution in the image optimiser.

### 13.4b Consistency audit — `scripts/audit.py`

**92 of 92 passed.** This is the check that stops the write-up from drifting away from the code. It reseeds a throwaway database and then verifies that every object count quoted in section 8 matches reality, that every function, trigger, index and view named anywhere in this document actually exists, that the security requirements hold in the app source (no hard-coded connection string, no string-concatenated SQL, bcrypt in use, `httpOnly` cookies, `.env.local` git-ignored), that the seed data is internally consistent (no orphaned merge links, no complaint that is its own parent, the denormalised counter correct), and that the relational schema diagram matches the live database table for table and key for key.

### 13.5 How to re-run everything

```bash
bash scripts/run_tests.sh            # throwaway DB, runs all 6 SQL files
bash scripts/concurrency_test.sh     # the two-session merge race
cd app && npm run build && npm start &
BASE=http://localhost:3000 bash scripts/api_test.sh
python3 scripts/audit.py             # docs/diagrams vs the real schema
```

---

## 14. Conclusion and future enhancements

### What was built

A working two-paradigm system where each paradigm does the job it is actually suited to. PostgreSQL holds the entities and enforces the rules; pgvector holds the complaint text and answers the similarity questions that SQL cannot. The two meet in single queries that filter structurally and rank semantically.

The project goes beyond CRUD in a specific, demonstrable way: the duplicate-detection and routing engine is the product, and the forms around it merely feed it. Both are measurable, and both were measured.

### What we would do differently

The demo embedding was added so the project could be demonstrated without a Python environment, and it works — but it set a ceiling on routing accuracy that took a while to recognise as a *data* problem rather than a *logic* problem. We changed the voting rule twice before realising the real limit was the 14-complaint history the vote was drawing on.

### Future enhancements

1. **Photo embeddings.** Citizens attach photos; `complaint_attachment` already stores the URLs. A CLIP image embedding alongside the text embedding would catch duplicates where two people describe the same pothole completely differently but photograph the same hole.
2. **Geographic clustering.** `latitude` and `longitude` are stored but currently unused in matching. Adding PostGIS and requiring candidate duplicates to fall within a radius would be stronger than the current ward filter, which is coarse.
3. **Routing confidence.** `fn_route_complaint` returns a department or `NULL`. Returning a confidence score as well would let the application auto-route only when confident and queue the rest for human triage — which directly addresses the 2-in-10 miss rate measured above.
4. **Feedback loop.** When staff override an automatic routing decision, that correction is signal. Recording overrides and preferring them when voting would let the system improve as it is used.
5. **Partitioning `status_history`.** The audit trail grows without bound. Range-partitioning it by month would keep queries fast once the table reaches millions of rows.

---

## Appendix A — Requirement coverage

| Spec requirement | Where it is satisfied |
|---|---|
| 1. Unique title, real problem, not CRUD | AEGIS; the routing and dedup engine is the product |
| 2. Two-member team with defined responsibilities | Appendix B |
| 3. SQL + vector (Option 2) | PostgreSQL 16 + pgvector |
| 4. ER diagram → relational schema | §5, §6; `diagrams/` |
| 5. DDL: CREATE/ALTER/DROP, keys, constraints, indexes, views | `db/01_schema.sql`; §9.1 |
| 6. DML: INSERT/UPDATE/DELETE/SELECT, JOIN, GROUP BY, HAVING, subqueries | `db/03_seed.sql`, `db/04_queries.sql`; §10 |
| Syllabus Unit 2: CTEs, window functions, full-text search | `db/06_advanced_queries.sql`; §10.1 |
| Syllabus Unit 3: functional dependencies, 1NF–BCNF | `docs/normalization.md`; §6.1 |
| Syllabus Unit 4: transactions, concurrency control, locking | §9.4; `scripts/concurrency_test.sh` |
| 7. Four or more advanced features | Six implemented; §9.2 |
| 8. Vector / semantic search, five questions answered | §9.3 |
| 9. Next.js web interface | `app/`; §11 |
| 10. API layer, no hard-coded credentials, env vars | `lib/db.js`, `app/.env.example` |
| 11. Authentication, minimum two roles | Citizen, Staff, Admin; `lib/auth.js` |
| 12. Database-level validation and integrity | 19 CHECKs, 15 FKs, validation trigger; tests group 1 |
| 13. Security: no plain-text passwords or credentials | bcrypt, HMAC-signed httpOnly cookies, parameterised queries, `.gitignore` |
| 14. Documentation (14 sections) | This document |
| 15. Git/GitHub with individual contributions and README | `README.md`; Appendix B |
| 16. Demonstration material | §12, §13 |
| 17. Originality | Original design; no tutorial or repository was copied |
| 18. Level 3: beyond CRUD, justified database choice | §1, §7 |

## Appendix B — Individual contribution

Fill this in with your own split before submission. The specification requires that both members contribute to *both* the database and the application, so divide by feature vertical rather than by layer.

| Area | Member A | Member B |
|---|---|---|
| Schema design and DDL | | |
| Triggers and constraints | | |
| Stored functions | | |
| Embedding pipeline | | |
| Citizen portal | | |
| Staff queue and merge UI | | |
| Admin dashboard | | |
| API routes and auth | | |
| Test suites | | |
| Documentation | | |

Keep commits attributed to the right author so the GitHub history matches this table.
