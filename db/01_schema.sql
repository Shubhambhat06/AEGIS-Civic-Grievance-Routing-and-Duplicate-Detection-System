-- =====================================================================
-- AEGIS - Civic Grievance Routing and Duplicate Detection System
-- File 1 of 5 : SCHEMA (DDL)
--
-- Covers: CREATE, ALTER, DROP, primary keys, foreign keys,
--         constraints, indexes, views
--
-- Target : PostgreSQL 16 with the pgvector extension
-- Run as : psql -U postgres -d aegis -f db/01_schema.sql
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. EXTENSIONS
-- ---------------------------------------------------------------------
-- pgvector gives us the VECTOR column type and similarity operators.
CREATE EXTENSION IF NOT EXISTS vector;


-- ---------------------------------------------------------------------
-- 1. DROP (so the script can be re-run safely during development)
--    Dropped child-first to respect foreign key dependencies.
-- ---------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_department_performance CASCADE;
DROP VIEW IF EXISTS v_citizen_complaints CASCADE;
DROP VIEW IF EXISTS v_open_queue        CASCADE;

DROP TABLE IF EXISTS feedback             CASCADE;
DROP TABLE IF EXISTS status_history       CASCADE;
DROP TABLE IF EXISTS duplicate_link       CASCADE;
DROP TABLE IF EXISTS complaint_embedding  CASCADE;
DROP TABLE IF EXISTS complaint_attachment CASCADE;
DROP TABLE IF EXISTS complaint            CASCADE;
DROP TABLE IF EXISTS staff                CASCADE;
DROP TABLE IF EXISTS department           CASCADE;
DROP TABLE IF EXISTS citizen_phone        CASCADE;
DROP TABLE IF EXISTS citizen              CASCADE;
DROP TABLE IF EXISTS ward                 CASCADE;

DROP TYPE IF EXISTS complaint_status   CASCADE;
DROP TYPE IF EXISTS complaint_priority CASCADE;
DROP TYPE IF EXISTS staff_role         CASCADE;


-- ---------------------------------------------------------------------
-- 2. ENUM TYPES
--    These three columns have a small, fixed set of legal values that
--    is shared by more than one table, so we define them once as types
--    instead of repeating a CHECK constraint in each table.
-- ---------------------------------------------------------------------
CREATE TYPE complaint_status AS ENUM (
    'OPEN',         -- filed by a citizen, not yet routed
    'ROUTED',       -- a department has been assigned
    'IN_PROGRESS',  -- a staff member is working on it
    'RESOLVED',     -- closed successfully
    'MERGED',       -- folded into a parent complaint as a duplicate
    'ESCALATED'     -- SLA deadline passed without resolution
);

CREATE TYPE complaint_priority AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');

CREATE TYPE staff_role AS ENUM ('STAFF', 'ADMIN');


-- ---------------------------------------------------------------------
-- 3. WARD
--    Municipal ward. A simple reference table used for grouping
--    complaints and citizens geographically.
-- ---------------------------------------------------------------------
CREATE TABLE ward (
    ward_id    SERIAL       PRIMARY KEY,
    ward_name  VARCHAR(80)  NOT NULL,
    zone       VARCHAR(40)  NOT NULL,

    CONSTRAINT uq_ward_name UNIQUE (ward_name),
    CONSTRAINT ck_ward_name CHECK (length(trim(ward_name)) >= 2)
);


-- ---------------------------------------------------------------------
-- 4. CITIZEN
--    A member of the public who files complaints. This is role 1 of the
--    two roles required by the project specification.
-- ---------------------------------------------------------------------
CREATE TABLE citizen (
    citizen_id     SERIAL        PRIMARY KEY,
    email          VARCHAR(120)  NOT NULL,
    full_name      VARCHAR(120)  NOT NULL,
    password_hash  VARCHAR(255)  NOT NULL,   -- bcrypt digest, never plain text
    ward_id        INT           NOT NULL,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT uq_citizen_email UNIQUE (email),
    CONSTRAINT fk_citizen_ward  FOREIGN KEY (ward_id)
        REFERENCES ward (ward_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT ck_citizen_email CHECK (email LIKE '%_@_%._%'),
    CONSTRAINT ck_citizen_name  CHECK (length(trim(full_name)) >= 2)
);


-- ---------------------------------------------------------------------
-- 5. CITIZEN_PHONE
--    In the ER diagram 'phone' is a multivalued attribute of CITIZEN.
--    The standard ER-to-relational mapping rule turns a multivalued
--    attribute into its own table whose primary key is the owner's key
--    plus the attribute itself.
-- ---------------------------------------------------------------------
CREATE TABLE citizen_phone (
    citizen_id  INT          NOT NULL,
    phone       VARCHAR(15)  NOT NULL,

    CONSTRAINT pk_citizen_phone PRIMARY KEY (citizen_id, phone),
    CONSTRAINT fk_citizen_phone FOREIGN KEY (citizen_id)
        REFERENCES citizen (citizen_id) ON DELETE CASCADE,

    CONSTRAINT ck_phone_format CHECK (phone ~ '^[0-9+][0-9]{7,14}$')
);


-- ---------------------------------------------------------------------
-- 6. DEPARTMENT
--    The municipal departments a complaint can be routed to
--    (Roads, Water Supply, Sanitation, and so on).
-- ---------------------------------------------------------------------
CREATE TABLE department (
    dept_id            SERIAL       PRIMARY KEY,
    dept_name          VARCHAR(80)  NOT NULL,
    category           VARCHAR(40)  NOT NULL,
    default_sla_hours  INT          NOT NULL DEFAULT 72,

    CONSTRAINT uq_department_name UNIQUE (dept_name),
    CONSTRAINT ck_department_sla  CHECK (default_sla_hours BETWEEN 1 AND 8760)
);


-- ---------------------------------------------------------------------
-- 7. STAFF
--    Municipal employees. This is role 2. The 'role' column separates
--    ordinary STAFF from ADMIN, giving the role-based access control
--    required by the specification.
-- ---------------------------------------------------------------------
CREATE TABLE staff (
    staff_id       SERIAL        PRIMARY KEY,
    email          VARCHAR(120)  NOT NULL,
    full_name      VARCHAR(120)  NOT NULL,
    password_hash  VARCHAR(255)  NOT NULL,
    role           staff_role    NOT NULL DEFAULT 'STAFF',
    dept_id        INT           NOT NULL,

    CONSTRAINT uq_staff_email UNIQUE (email),
    CONSTRAINT fk_staff_dept  FOREIGN KEY (dept_id)
        REFERENCES department (dept_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT ck_staff_email CHECK (email LIKE '%_@_%._%')
);


-- ---------------------------------------------------------------------
-- 8. COMPLAINT
--    The central table of the system.
--
--    Two design notes worth remembering:
--
--    (a) dept_id and assigned_staff_id are deliberately NULLable.
--        A complaint exists from the moment the citizen submits it,
--        which is before routing and before a staff member picks it up.
--
--    (b) sla_deadline is stored, not computed on the fly from
--        department.default_sla_hours. It is a snapshot taken when the
--        complaint is filed, so that changing a department's SLA policy
--        later does not silently move the deadline of old complaints.
-- ---------------------------------------------------------------------
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
    CONSTRAINT fk_complaint_ward FOREIGN KEY (ward_id)
        REFERENCES ward (ward_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_complaint_staff FOREIGN KEY (assigned_staff_id)
        REFERENCES staff (staff_id) ON UPDATE CASCADE ON DELETE SET NULL,

    CONSTRAINT ck_complaint_title CHECK (length(trim(title)) >= 5),
    CONSTRAINT ck_complaint_desc  CHECK (length(trim(description)) >= 15),
    CONSTRAINT ck_complaint_lat   CHECK (latitude  IS NULL OR latitude  BETWEEN  -90 AND  90),
    CONSTRAINT ck_complaint_lon   CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    -- latitude and longitude are a pair: either both present or both absent
    CONSTRAINT ck_complaint_geo   CHECK ((latitude IS NULL) = (longitude IS NULL)),
    CONSTRAINT ck_complaint_sla   CHECK (sla_deadline > filed_at),
    CONSTRAINT ck_complaint_closed CHECK (resolved_at IS NULL OR resolved_at >= filed_at),
    -- a complaint marked RESOLVED must carry a resolution timestamp
    CONSTRAINT ck_complaint_resolved_consistency
        CHECK (status <> 'RESOLVED' OR resolved_at IS NOT NULL)
);


-- ---------------------------------------------------------------------
-- 9. COMPLAINT_ATTACHMENT
--    'attachment_url' is the second multivalued attribute in the ER
--    diagram and is mapped the same way as citizen_phone.
-- ---------------------------------------------------------------------
CREATE TABLE complaint_attachment (
    complaint_id    INT           NOT NULL,
    attachment_url  VARCHAR(500)  NOT NULL,

    CONSTRAINT pk_complaint_attachment PRIMARY KEY (complaint_id, attachment_url),
    CONSTRAINT fk_attachment_complaint FOREIGN KEY (complaint_id)
        REFERENCES complaint (complaint_id) ON DELETE CASCADE
);


-- ---------------------------------------------------------------------
-- 10. COMPLAINT_EMBEDDING
--     The vector half of the project. One row per complaint holding the
--     384-dimension embedding of its description.
--
--     Why a separate table rather than a column on complaint:
--       - the embedding is produced after the complaint is inserted,
--         so at insert time there is nothing to store;
--       - a 384-float vector is roughly 1.5 KB, and keeping it out of
--         the main table means ordinary complaint queries do not have
--         to read it.
--     Making the foreign key also the primary key enforces the 1:1.
-- ---------------------------------------------------------------------
CREATE TABLE complaint_embedding (
    complaint_id  INT          PRIMARY KEY,
    embedding     VECTOR(384)  NOT NULL,
    model_name    VARCHAR(60)  NOT NULL DEFAULT 'all-MiniLM-L6-v2',
    generated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT fk_embedding_complaint FOREIGN KEY (complaint_id)
        REFERENCES complaint (complaint_id) ON DELETE CASCADE
);


-- ---------------------------------------------------------------------
-- 11. DUPLICATE_LINK
--     Records that one complaint was merged into another.
--
--     This is a table rather than a simple parent_id column on complaint
--     because the merge carries information of its own: the similarity
--     score that justified it, who approved it, and when. Keeping that
--     information means a wrong merge can be audited and undone.
--
--     UNIQUE is implied by the primary key on child_complaint_id:
--     a complaint can be merged into at most one parent.
-- ---------------------------------------------------------------------
CREATE TABLE duplicate_link (
    child_complaint_id   INT          PRIMARY KEY,
    parent_complaint_id  INT          NOT NULL,
    similarity_score     REAL         NOT NULL,
    merged_by            INT,
    merged_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT fk_dup_child FOREIGN KEY (child_complaint_id)
        REFERENCES complaint (complaint_id) ON DELETE CASCADE,
    CONSTRAINT fk_dup_parent FOREIGN KEY (parent_complaint_id)
        REFERENCES complaint (complaint_id) ON DELETE CASCADE,
    CONSTRAINT fk_dup_staff FOREIGN KEY (merged_by)
        REFERENCES staff (staff_id) ON DELETE SET NULL,

    -- a complaint cannot be a duplicate of itself
    CONSTRAINT ck_dup_not_self CHECK (child_complaint_id <> parent_complaint_id),
    CONSTRAINT ck_dup_score    CHECK (similarity_score BETWEEN 0 AND 1)
);


-- ---------------------------------------------------------------------
-- 12. STATUS_HISTORY
--     An append-only audit trail. Every status change is written here
--     automatically by a trigger (see 02_functions.sql).
--
--     The primary key is (complaint_id, changed_at): in the ER diagram
--     STATUS_HISTORY is a weak entity whose partial key is changed_at.
-- ---------------------------------------------------------------------
CREATE TABLE status_history (
    complaint_id  INT               NOT NULL,
    changed_at    TIMESTAMPTZ       NOT NULL DEFAULT clock_timestamp(),
    old_status    complaint_status,                -- NULL on the first row
    new_status    complaint_status  NOT NULL,
    changed_by    INT,                             -- NULL if a trigger did it
    remarks       TEXT,

    CONSTRAINT pk_status_history PRIMARY KEY (complaint_id, changed_at),
    CONSTRAINT fk_history_complaint FOREIGN KEY (complaint_id)
        REFERENCES complaint (complaint_id) ON DELETE CASCADE,
    CONSTRAINT fk_history_staff FOREIGN KEY (changed_by)
        REFERENCES staff (staff_id) ON DELETE SET NULL,

    CONSTRAINT ck_history_changed CHECK (old_status IS DISTINCT FROM new_status)
);


-- ---------------------------------------------------------------------
-- 13. FEEDBACK
--     Optional rating left by the citizen after resolution.
--     One complaint has at most one feedback row, which is why
--     complaint_id alone is the primary key.
-- ---------------------------------------------------------------------
CREATE TABLE feedback (
    complaint_id  INT          PRIMARY KEY,
    submitted_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    rating        SMALLINT     NOT NULL,
    comments      TEXT,

    CONSTRAINT fk_feedback_complaint FOREIGN KEY (complaint_id)
        REFERENCES complaint (complaint_id) ON DELETE CASCADE,
    CONSTRAINT ck_feedback_rating CHECK (rating BETWEEN 1 AND 5)
);


-- =====================================================================
-- 14. ALTER TABLE
--     Three realistic schema changes, kept in the script so the use of
--     ALTER is visible in the submitted code.
-- =====================================================================

-- (a) Add a counter that the merge trigger maintains, so the staff queue
--     can show "reported by 12 people" without a COUNT(*) every time.
ALTER TABLE complaint
    ADD COLUMN duplicate_count INT NOT NULL DEFAULT 0;

ALTER TABLE complaint
    ADD CONSTRAINT ck_complaint_dupcount CHECK (duplicate_count >= 0);

-- (b) Add the generated full-text search column. A generated column is
--     kept in sync by PostgreSQL itself, so no trigger is needed.
ALTER TABLE complaint
    ADD COLUMN search_tsv TSVECTOR
    GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(title, '')),       'A') ||
        setweight(to_tsvector('english', coalesce(description, '')), 'B')
    ) STORED;

-- (c) Widen a column that turned out to be too small in practice.
ALTER TABLE department
    ALTER COLUMN category TYPE VARCHAR(60);


-- =====================================================================
-- 15. INDEXES
--     Every index here exists to serve a specific query in the
--     application. They are not added speculatively.
-- =====================================================================

-- Vector similarity search, used for duplicate detection and routing.
-- HNSW with cosine distance, matching the <=> operator used in queries.
CREATE INDEX idx_embedding_hnsw
    ON complaint_embedding USING hnsw (embedding vector_cosine_ops);

-- Keyword search box on the citizen portal.
CREATE INDEX idx_complaint_fts
    ON complaint USING GIN (search_tsv);

-- Department work queue: "show my department's complaints, newest first".
CREATE INDEX idx_complaint_dept_filed
    ON complaint (dept_id, filed_at DESC);

-- Citizen portal: "my complaints".
CREATE INDEX idx_complaint_citizen
    ON complaint (citizen_id, filed_at DESC);

-- The SLA sweep only ever looks at complaints that are still live.
-- A partial index stays small even as the resolved archive grows.
CREATE INDEX idx_complaint_sla_open
    ON complaint (sla_deadline)
    WHERE status NOT IN ('RESOLVED', 'MERGED');

-- Staff workload view.
CREATE INDEX idx_complaint_staff_status
    ON complaint (assigned_staff_id, status)
    WHERE assigned_staff_id IS NOT NULL;

-- Ward-level reporting.
CREATE INDEX idx_complaint_ward
    ON complaint (ward_id);

-- "Show me every complaint merged into this one".
CREATE INDEX idx_dup_parent
    ON duplicate_link (parent_complaint_id);


-- =====================================================================
-- 16. VIEWS
-- =====================================================================

-- Staff work queue, ordered by how close the SLA deadline is.
-- Merged and resolved complaints are excluded so the queue only shows
-- real outstanding work.
CREATE VIEW v_open_queue AS
SELECT
    c.complaint_id,
    c.title,
    c.priority,
    c.status,
    d.dept_name,
    w.ward_name,
    s.full_name AS assigned_to,
    c.filed_at,
    c.sla_deadline,
    ROUND(EXTRACT(EPOCH FROM (c.sla_deadline - now())) / 3600.0, 1) AS hours_remaining,
    (c.sla_deadline < now()) AS is_breached,
    c.duplicate_count
FROM complaint c
JOIN      ward       w ON w.ward_id  = c.ward_id
LEFT JOIN department d ON d.dept_id  = c.dept_id
LEFT JOIN staff      s ON s.staff_id = c.assigned_staff_id
WHERE c.status NOT IN ('RESOLVED', 'MERGED');


-- Citizen-facing view. If the citizen's complaint was merged into
-- another one, this shows the parent complaint's title and status so the
-- citizen can still follow progress.
CREATE VIEW v_citizen_complaints AS
SELECT
    c.complaint_id,
    c.citizen_id,
    c.title,
    c.status,
    c.filed_at,
    c.resolved_at,
    dl.parent_complaint_id,
    p.title  AS merged_into_title,
    p.status AS merged_into_status
FROM complaint c
LEFT JOIN duplicate_link dl ON dl.child_complaint_id = c.complaint_id
LEFT JOIN complaint      p  ON p.complaint_id        = dl.parent_complaint_id;


-- Admin dashboard. This one is materialized because it aggregates the
-- whole complaint table and is read on every dashboard load, but it only
-- needs to be accurate to within a refresh cycle.
CREATE MATERIALIZED VIEW mv_department_performance AS
SELECT
    d.dept_id,
    d.dept_name,
    COUNT(c.complaint_id)                                         AS total_complaints,
    COUNT(*) FILTER (WHERE c.status = 'RESOLVED')                 AS resolved_count,
    COUNT(*) FILTER (WHERE c.status = 'ESCALATED')                AS escalated_count,
    COUNT(*) FILTER (WHERE c.status NOT IN ('RESOLVED','MERGED')) AS open_count,
    ROUND(AVG(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at)) / 3600.0)::NUMERIC, 2)
                                                                  AS avg_resolution_hours,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE c.resolved_at > c.sla_deadline)
        / NULLIF(COUNT(*) FILTER (WHERE c.resolved_at IS NOT NULL), 0)
    , 2)                                                          AS sla_breach_pct
FROM department d
LEFT JOIN complaint c ON c.dept_id = d.dept_id
GROUP BY d.dept_id, d.dept_name;

-- A unique index is required before REFRESH ... CONCURRENTLY can be used.
CREATE UNIQUE INDEX idx_mv_dept_perf ON mv_department_performance (dept_id);

-- Refresh with:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_department_performance;
