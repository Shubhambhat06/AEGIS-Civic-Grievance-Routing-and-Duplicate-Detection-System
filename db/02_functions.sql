-- =====================================================================
-- AEGIS - File 2 of 5 : STORED FUNCTIONS, TRIGGERS, TRANSACTIONS
--
-- This file contains four of the six advanced database features:
--   - stored functions
--   - triggers
--   - transactions (inside fn_merge_duplicate)
--   - vector similarity search (inside fn_find_duplicates / fn_route)
--
-- Run as: psql -U postgres -d aegis -f db/02_functions.sql
-- =====================================================================


-- =====================================================================
-- PART A - STORED FUNCTIONS
-- =====================================================================

-- ---------------------------------------------------------------------
-- A1. fn_find_duplicates
--     Given a complaint, return the most similar earlier complaints.
--
--     How it works:
--       - every complaint description is stored as a 384-dimension
--         embedding in complaint_embedding;
--       - the <=> operator is pgvector's cosine distance (0 = identical,
--         2 = opposite), so similarity = 1 - distance;
--       - we only compare against complaints in the same ward, because
--         two potholes in different parts of the city are not the same
--         pothole however similar the wording is.
--
--     Returns candidates above the given similarity threshold.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_find_duplicates(
    p_complaint_id  INT,
    p_threshold     REAL DEFAULT 0.80,
    p_limit         INT  DEFAULT 5
)
RETURNS TABLE (
    candidate_id      INT,
    candidate_title   VARCHAR(150),
    candidate_status  complaint_status,
    similarity        REAL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_embedding VECTOR(384);
    v_ward_id   INT;
    v_filed_at  TIMESTAMPTZ;
BEGIN
    -- Fetch the subject complaint's own embedding and ward.
    SELECT e.embedding, c.ward_id, c.filed_at
      INTO v_embedding, v_ward_id, v_filed_at
      FROM complaint c
      JOIN complaint_embedding e ON e.complaint_id = c.complaint_id
     WHERE c.complaint_id = p_complaint_id;

    IF v_embedding IS NULL THEN
        -- No embedding yet (the pipeline has not run). Return nothing
        -- rather than raising, so the application can carry on.
        RETURN;
    END IF;

    RETURN QUERY
    SELECT c.complaint_id,
           c.title,
           c.status,
           (1 - (e.embedding <=> v_embedding))::REAL AS similarity
      FROM complaint c
      JOIN complaint_embedding e ON e.complaint_id = c.complaint_id
     WHERE c.complaint_id <> p_complaint_id
       AND c.ward_id       = v_ward_id
       AND c.filed_at      < v_filed_at      -- only earlier complaints
       AND c.status       <> 'MERGED'        -- never merge into a duplicate
       AND (1 - (e.embedding <=> v_embedding)) >= p_threshold
     ORDER BY e.embedding <=> v_embedding
     LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION fn_find_duplicates IS
    'Vector similarity search: finds earlier complaints in the same ward that look like duplicates.';


-- ---------------------------------------------------------------------
-- A2. fn_route_complaint
--     Decide which department a complaint belongs to.
--
--     The idea: find the most similar complaints that were already
--     resolved, and route to the department that handled them. In other
--     words, learn the routing rule from history instead of hard-coding
--     a keyword list.
--
--     The vote is WEIGHTED BY SIMILARITY, not a plain head count. A
--     plain count lets a department that simply appears more often in
--     the archive outvote the one department whose complaint is an
--     obvious match. We sum the SQUARE of each neighbour's similarity,
--     which sharpens the vote: one neighbour at 0.60 (0.36) outweighs
--     two at 0.40 (0.16 each), so a clear match wins over a pile of
--     loosely related ones.
--
--     Neighbours below p_min_similarity are ignored entirely, so an
--     unrelated complaint does not get routed on the strength of weak
--     matches. If nothing clears the bar the function returns NULL and
--     the complaint waits for manual triage.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_route_complaint(
    p_complaint_id    INT,
    p_neighbours      INT  DEFAULT 5,
    p_min_similarity  REAL DEFAULT 0.15
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_embedding VECTOR(384);
    v_dept_id   INT;
BEGIN
    SELECT e.embedding INTO v_embedding
      FROM complaint_embedding e
     WHERE e.complaint_id = p_complaint_id;

    IF v_embedding IS NULL THEN
        RETURN NULL;
    END IF;

    -- Take the N nearest resolved complaints that clear the similarity
    -- floor, then pick the department with the highest total weight.
    SELECT dept_id INTO v_dept_id
    FROM (
        SELECT c.dept_id,
               power(1 - (e.embedding <=> v_embedding), 2)::REAL AS weight
          FROM complaint c
          JOIN complaint_embedding e ON e.complaint_id = c.complaint_id
         WHERE c.status  = 'RESOLVED'
           AND c.dept_id IS NOT NULL
           AND c.complaint_id <> p_complaint_id
           AND (1 - (e.embedding <=> v_embedding)) >= p_min_similarity
         ORDER BY e.embedding <=> v_embedding
         LIMIT p_neighbours
    ) AS neighbours
    GROUP BY dept_id
    ORDER BY SUM(weight) DESC
    LIMIT 1;

    RETURN v_dept_id;
END;
$$;

COMMENT ON FUNCTION fn_route_complaint IS
    'Routes a complaint by majority vote over the departments that resolved the most similar past complaints.';


-- ---------------------------------------------------------------------
-- A3. fn_merge_duplicate
--     Merge one complaint into another as a duplicate.
--
--     This is the TRANSACTION demonstration. Three things must happen
--     together or not at all:
--       1. record the link in duplicate_link,
--       2. set the child's status to MERGED,
--       3. increment the parent's duplicate_count.
--
--     A PL/pgSQL function runs inside a single transaction, so if any
--     statement raises, every change made by the function is rolled
--     back. The explicit validation checks below raise on bad input,
--     which is what makes the rollback happen.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_merge_duplicate(
    p_child_id    INT,
    p_parent_id   INT,
    p_similarity  REAL,
    p_staff_id    INT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_child_status  complaint_status;
    v_parent_status complaint_status;
BEGIN
    -- Validation 1: a complaint cannot be a duplicate of itself.
    IF p_child_id = p_parent_id THEN
        RAISE EXCEPTION 'A complaint cannot be merged into itself (id %)', p_child_id;
    END IF;

    -- Lock both rows so two staff members cannot merge the same pair
    -- at the same moment.
    SELECT status INTO v_child_status
      FROM complaint WHERE complaint_id = p_child_id FOR UPDATE;
    SELECT status INTO v_parent_status
      FROM complaint WHERE complaint_id = p_parent_id FOR UPDATE;

    -- Validation 2: both complaints must exist.
    IF v_child_status IS NULL OR v_parent_status IS NULL THEN
        RAISE EXCEPTION 'Complaint % or % does not exist', p_child_id, p_parent_id;
    END IF;

    -- Validation 3: never merge into something that is itself a duplicate,
    -- otherwise we build chains of merges that are hard to follow.
    IF v_parent_status = 'MERGED' THEN
        RAISE EXCEPTION 'Complaint % is itself a duplicate and cannot be a parent', p_parent_id;
    END IF;

    -- Validation 4: do not merge a complaint that is already resolved.
    IF v_child_status IN ('RESOLVED', 'MERGED') THEN
        RAISE EXCEPTION 'Complaint % is already % and cannot be merged',
                        p_child_id, v_child_status;
    END IF;

    -- Step 1: record the link.
    INSERT INTO duplicate_link
        (child_complaint_id, parent_complaint_id, similarity_score, merged_by)
    VALUES
        (p_child_id, p_parent_id, p_similarity, p_staff_id);

    -- Step 2: mark the child merged.
    --         The status trigger writes the audit row automatically.
    UPDATE complaint
       SET status = 'MERGED'
     WHERE complaint_id = p_child_id;

    -- Step 3: bump the parent's counter.
    UPDATE complaint
       SET duplicate_count = duplicate_count + 1
     WHERE complaint_id = p_parent_id;
END;
$$;

COMMENT ON FUNCTION fn_merge_duplicate IS
    'Atomically links a duplicate to its parent, marks it MERGED and increments the parent counter.';


-- ---------------------------------------------------------------------
-- A4. fn_file_complaint
--     Insert a complaint and set its SLA deadline from the department's
--     policy (or a 72-hour default when the department is not yet known).
--     Keeping this in one function means the deadline rule lives in one
--     place rather than being repeated in the application code.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_file_complaint(
    p_citizen_id   INT,
    p_ward_id      INT,
    p_title        VARCHAR(150),
    p_description  TEXT,
    p_priority     complaint_priority DEFAULT 'MEDIUM',
    p_latitude     NUMERIC(9,6)       DEFAULT NULL,
    p_longitude    NUMERIC(9,6)       DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_complaint_id INT;
    v_sla_hours    INT := 72;
BEGIN
    INSERT INTO complaint
        (citizen_id, ward_id, title, description, priority,
         latitude, longitude, sla_deadline)
    VALUES
        (p_citizen_id, p_ward_id, p_title, p_description, p_priority,
         p_latitude, p_longitude, now() + make_interval(hours => v_sla_hours))
    RETURNING complaint_id INTO v_complaint_id;

    RETURN v_complaint_id;
END;
$$;


-- =====================================================================
-- PART B - TRIGGERS
-- =====================================================================

-- ---------------------------------------------------------------------
-- B1. Audit trigger: log every status change into status_history.
--
--     Writing this as a trigger rather than application code guarantees
--     the audit trail is complete: it fires no matter whether the change
--     came from the web app, a stored function, or a manual psql UPDATE.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_log_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO status_history (complaint_id, old_status, new_status, remarks)
        VALUES (NEW.complaint_id, NULL, NEW.status, 'Complaint filed');

    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO status_history (complaint_id, old_status, new_status, changed_by)
        VALUES (NEW.complaint_id, OLD.status, NEW.status, NEW.assigned_staff_id);
    END IF;

    RETURN NULL;   -- AFTER trigger, return value is ignored
END;
$$;

CREATE TRIGGER t_complaint_status_audit
    AFTER INSERT OR UPDATE OF status ON complaint
    FOR EACH ROW
    EXECUTE FUNCTION trg_log_status_change();


-- ---------------------------------------------------------------------
-- B2. Validation trigger: stamp resolved_at and block illegal
--     status transitions.
--
--     This is the database-level input validation the specification
--     asks for. Even if the web application has a bug, the database
--     refuses to move a complaint backwards out of a closed state.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_validate_status_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Setting a complaint to RESOLVED stamps the resolution time
    -- automatically, which also satisfies ck_complaint_resolved_consistency.
    IF NEW.status = 'RESOLVED' AND NEW.resolved_at IS NULL THEN
        NEW.resolved_at := now();
    END IF;

    -- A resolved or merged complaint is closed. It must not be reopened
    -- by a plain UPDATE.
    IF TG_OP = 'UPDATE'
       AND OLD.status IN ('RESOLVED', 'MERGED')
       AND NEW.status NOT IN ('RESOLVED', 'MERGED') THEN
        RAISE EXCEPTION 'Complaint % is % and cannot be reopened',
                        OLD.complaint_id, OLD.status;
    END IF;

    -- A complaint cannot be marked IN_PROGRESS with nobody working on it.
    IF NEW.status = 'IN_PROGRESS' AND NEW.assigned_staff_id IS NULL THEN
        RAISE EXCEPTION 'Complaint % cannot be IN_PROGRESS with no assigned staff',
                        NEW.complaint_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER t_complaint_validate
    BEFORE INSERT OR UPDATE ON complaint
    FOR EACH ROW
    EXECUTE FUNCTION trg_validate_status_transition();


-- ---------------------------------------------------------------------
-- B3. Routing trigger: when an embedding arrives for a complaint that
--     has not been routed yet, route it automatically.
--
--     The embedding pipeline inserts into complaint_embedding; this
--     trigger reacts to that insert, so routing happens without the
--     pipeline needing to know anything about departments.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_auto_route()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_dept_id   INT;
    v_sla_hours INT;
BEGIN
    -- Only act on complaints that are still unrouted.
    IF EXISTS (SELECT 1 FROM complaint
                WHERE complaint_id = NEW.complaint_id
                  AND dept_id IS NULL
                  AND status = 'OPEN') THEN

        v_dept_id := fn_route_complaint(NEW.complaint_id);

        IF v_dept_id IS NOT NULL THEN
            SELECT default_sla_hours INTO v_sla_hours
              FROM department WHERE dept_id = v_dept_id;

            UPDATE complaint
               SET dept_id      = v_dept_id,
                   status       = 'ROUTED',
                   sla_deadline = filed_at + make_interval(hours => v_sla_hours)
             WHERE complaint_id = NEW.complaint_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER t_embedding_auto_route
    AFTER INSERT ON complaint_embedding
    FOR EACH ROW
    EXECUTE FUNCTION trg_auto_route();


-- =====================================================================
-- PART C - SLA ESCALATION
-- =====================================================================

-- ---------------------------------------------------------------------
-- C1. fn_escalate_overdue
--     Move every live complaint whose deadline has passed into the
--     ESCALATED state. Returns how many rows it changed.
--
--     Run this on a schedule (cron, or a Next.js route called by a
--     scheduler). It is written as a set-based UPDATE rather than a
--     row-by-row loop so it stays fast as the table grows, and it uses
--     the partial index idx_complaint_sla_open.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_escalate_overdue()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE complaint
       SET status = 'ESCALATED'
     WHERE status IN ('OPEN', 'ROUTED', 'IN_PROGRESS')
       AND sla_deadline < now();

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION fn_escalate_overdue IS
    'Marks every live complaint past its SLA deadline as ESCALATED. Returns the number escalated.';
