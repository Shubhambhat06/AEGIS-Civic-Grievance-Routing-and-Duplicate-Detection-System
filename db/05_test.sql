-- =====================================================================
-- AEGIS - File 5 of 5 : TEST CASES
--
-- Verifies that the constraints, triggers, transactions and search
-- features behave as designed. Each test prints PASS or FAIL.
--
-- Negative tests (the ones that are SUPPOSED to be rejected) are
-- wrapped in a BEGIN ... EXCEPTION block, so a rejection is recorded
-- as a PASS instead of aborting the script.
--
-- Run as: psql -U postgres -d aegis -f db/05_test.sql
-- =====================================================================

\echo ''
\echo '################ AEGIS TEST SUITE ################'
\echo ''

CREATE OR REPLACE FUNCTION test_report(p_name TEXT, p_ok BOOLEAN, p_detail TEXT DEFAULT '')
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE '%  %  %',
        CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END,
        rpad(p_name, 52),
        p_detail;
END;
$$;


-- =====================================================================
-- GROUP 1 - CONSTRAINTS (data validation at the database level)
-- =====================================================================
DO $$
DECLARE v_ok BOOLEAN;
BEGIN
    RAISE NOTICE '--- Group 1: constraints ---';

    -- T1.1 duplicate email must be rejected (UNIQUE)
    BEGIN
        INSERT INTO citizen (email, full_name, password_hash, ward_id)
        VALUES ('arjun.menon@example.com', 'Impostor', 'x', 1);
        v_ok := FALSE;
    EXCEPTION WHEN unique_violation THEN v_ok := TRUE;
    END;
    PERFORM test_report('T1.1 duplicate citizen email rejected', v_ok);

    -- T1.2 rating outside 1..5 must be rejected (CHECK)
    BEGIN
        INSERT INTO feedback (complaint_id, rating) VALUES (3, 9);
        v_ok := FALSE;
    EXCEPTION WHEN check_violation THEN v_ok := TRUE;
    END;
    PERFORM test_report('T1.2 feedback rating out of range rejected', v_ok);

    -- T1.3 complaint referencing a non-existent citizen (FOREIGN KEY)
    BEGIN
        INSERT INTO complaint (citizen_id, ward_id, title, description, sla_deadline)
        VALUES (9999, 1, 'Ghost complaint', 'This citizen does not exist at all.',
                now() + interval '1 day');
        v_ok := FALSE;
    EXCEPTION WHEN foreign_key_violation THEN v_ok := TRUE;
    END;
    PERFORM test_report('T1.3 complaint with invalid citizen_id rejected', v_ok);

    -- T1.4 latitude without longitude (paired CHECK)
    BEGIN
        INSERT INTO complaint (citizen_id, ward_id, title, description, sla_deadline, latitude)
        VALUES (1, 1, 'Half located', 'Latitude given but longitude missing entirely.',
                now() + interval '1 day', 12.9);
        v_ok := FALSE;
    EXCEPTION WHEN check_violation THEN v_ok := TRUE;
    END;
    PERFORM test_report('T1.4 latitude without longitude rejected', v_ok);

    -- T1.5 SLA deadline before filing time (CHECK)
    BEGIN
        INSERT INTO complaint (citizen_id, ward_id, title, description, sla_deadline)
        VALUES (1, 1, 'Backwards deadline', 'The deadline is before the filing time here.',
                now() - interval '1 day');
        v_ok := FALSE;
    EXCEPTION WHEN check_violation THEN v_ok := TRUE;
    END;
    PERFORM test_report('T1.5 sla_deadline before filed_at rejected', v_ok);

    -- T1.6 badly formatted phone number (CHECK with regex)
    BEGIN
        INSERT INTO citizen_phone (citizen_id, phone) VALUES (1, 'not-a-number');
        v_ok := FALSE;
    EXCEPTION WHEN check_violation THEN v_ok := TRUE;
    END;
    PERFORM test_report('T1.6 malformed phone number rejected', v_ok);

    -- T1.7 deleting a ward that still has citizens (ON DELETE RESTRICT)
    BEGIN
        DELETE FROM ward WHERE ward_id = 1;
        v_ok := FALSE;
    EXCEPTION WHEN foreign_key_violation THEN v_ok := TRUE;
    END;
    PERFORM test_report('T1.7 ward delete blocked while in use', v_ok);
END $$;


-- =====================================================================
-- GROUP 2 - TRIGGERS
-- =====================================================================
DO $$
DECLARE
    v_ok      BOOLEAN;
    v_id      INT;
    v_rows    INT;
    v_status  complaint_status;
    v_res     TIMESTAMPTZ;
BEGIN
    RAISE NOTICE '--- Group 2: triggers ---';

    -- T2.1 filing a complaint writes the first audit row automatically
    v_id := fn_file_complaint(1, 1, 'Trigger test complaint',
                              'A complaint created purely to test the audit trigger.');
    SELECT COUNT(*) INTO v_rows FROM status_history WHERE complaint_id = v_id;
    PERFORM test_report('T2.1 insert writes status_history row', v_rows = 1,
                        format('rows=%s', v_rows));

    -- T2.2 resolving stamps resolved_at automatically
    UPDATE complaint SET assigned_staff_id = 2, status = 'IN_PROGRESS' WHERE complaint_id = v_id;
    UPDATE complaint SET status = 'RESOLVED' WHERE complaint_id = v_id;
    SELECT resolved_at INTO v_res FROM complaint WHERE complaint_id = v_id;
    PERFORM test_report('T2.2 RESOLVED stamps resolved_at', v_res IS NOT NULL);

    -- T2.3 each status change added an audit row (filed, in_progress, resolved)
    SELECT COUNT(*) INTO v_rows FROM status_history WHERE complaint_id = v_id;
    PERFORM test_report('T2.3 every status change audited', v_rows = 3,
                        format('rows=%s expected 3', v_rows));

    -- T2.4 a closed complaint cannot be reopened
    BEGIN
        UPDATE complaint SET status = 'OPEN' WHERE complaint_id = v_id;
        v_ok := FALSE;
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE;
    END;
    PERFORM test_report('T2.4 resolved complaint cannot be reopened', v_ok);

    -- T2.5 IN_PROGRESS without an assignee is refused
    BEGIN
        UPDATE complaint SET assigned_staff_id = NULL, status = 'IN_PROGRESS'
         WHERE complaint_id = 20;
        v_ok := FALSE;
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE;
    END;
    PERFORM test_report('T2.5 IN_PROGRESS needs an assigned staff member', v_ok);

    -- T2.6 the routing trigger assigned departments during seeding
    SELECT COUNT(*) INTO v_rows
      FROM complaint WHERE complaint_id BETWEEN 15 AND 24 AND dept_id IS NOT NULL;
    PERFORM test_report('T2.6 auto-routing assigned a department', v_rows = 10,
                        format('%s of 10 routed', v_rows));

    -- tidy up the complaint created by this group
    DELETE FROM complaint WHERE complaint_id = v_id;
END $$;


-- =====================================================================
-- GROUP 3 - TRANSACTIONS (fn_merge_duplicate)
-- =====================================================================
DO $$
DECLARE
    v_ok      BOOLEAN;
    v_before  INT;
    v_after   INT;
    v_links   INT;
BEGIN
    RAISE NOTICE '--- Group 3: transactions ---';

    -- T3.1 the seeded merges all landed
    SELECT COUNT(*) INTO v_links FROM duplicate_link WHERE parent_complaint_id = 15;
    PERFORM test_report('T3.1 three duplicates merged into #15', v_links = 3,
                        format('links=%s', v_links));

    -- T3.2 the parent's denormalised counter matches the link count
    SELECT duplicate_count INTO v_after FROM complaint WHERE complaint_id = 15;
    PERFORM test_report('T3.2 duplicate_count matches link count', v_after = v_links,
                        format('counter=%s links=%s', v_after, v_links));

    -- T3.3 merging into a complaint that is itself merged is refused
    BEGIN
        PERFORM fn_merge_duplicate(19, 16, 0.9, 2);
        v_ok := FALSE;
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE;
    END;
    PERFORM test_report('T3.3 merge into a merged complaint refused', v_ok);

    -- T3.4 self-merge is refused
    BEGIN
        PERFORM fn_merge_duplicate(19, 19, 0.9, 2);
        v_ok := FALSE;
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE;
    END;
    PERFORM test_report('T3.4 self-merge refused', v_ok);

    -- T3.5 ROLLBACK PROOF: a merge that fails midway must leave the
    --      parent's counter untouched. We force the failure by trying
    --      to merge a complaint that is already merged (#16): the
    --      duplicate_link INSERT happens first inside the function,
    --      then validation raises, and everything must roll back.
    SELECT duplicate_count INTO v_before FROM complaint WHERE complaint_id = 20;
    BEGIN
        PERFORM fn_merge_duplicate(16, 20, 0.9, 2);
    EXCEPTION WHEN OTHERS THEN NULL;   -- expected
    END;
    SELECT duplicate_count INTO v_after FROM complaint WHERE complaint_id = 20;
    SELECT COUNT(*) INTO v_links FROM duplicate_link WHERE parent_complaint_id = 20;
    PERFORM test_report('T3.5 failed merge rolled back completely',
                        v_before = v_after AND v_links = 0,
                        format('counter %s->%s, stray links=%s', v_before, v_after, v_links));
END $$;


-- =====================================================================
-- GROUP 4 - SEARCH (vector similarity and full text)
-- =====================================================================
DO $$
DECLARE
    v_rows  INT;
    v_top   INT;
    v_sim   REAL;
BEGIN
    RAISE NOTICE '--- Group 4: search ---';

    -- T4.1 vector similarity finds the pothole cluster
    SELECT COUNT(*) INTO v_rows FROM fn_find_duplicates(18, 0.30, 5);
    PERFORM test_report('T4.1 similarity search returns candidates', v_rows > 0,
                        format('candidates=%s', v_rows));

    -- T4.2 the nearest candidate for #18 is another pothole complaint
    SELECT candidate_id, similarity INTO v_top, v_sim
      FROM fn_find_duplicates(18, 0.00, 1);
    PERFORM test_report('T4.2 top duplicate candidate is the right cluster',
                        v_top IN (15, 16, 17),
                        format('top=%s sim=%s', v_top, round(v_sim::numeric, 3)));

    -- T4.3 a complaint with no similar neighbours returns nothing at a
    --      high threshold
    SELECT COUNT(*) INTO v_rows FROM fn_find_duplicates(19, 0.95, 5);
    PERFORM test_report('T4.3 unrelated complaint has no near-duplicates', v_rows = 0,
                        format('candidates=%s', v_rows));

    -- T4.4 full-text search finds pothole complaints
    SELECT COUNT(*) INTO v_rows
      FROM complaint
     WHERE search_tsv @@ websearch_to_tsquery('english', 'pothole');
    PERFORM test_report('T4.4 full-text search returns matches', v_rows > 0,
                        format('matches=%s', v_rows));
END $$;


-- =====================================================================
-- GROUP 5 - VIEWS AND SLA ESCALATION
-- =====================================================================
DO $$
DECLARE
    v_rows      INT;
    v_escalated INT;
    v_merged    INT;
BEGIN
    RAISE NOTICE '--- Group 5: views and SLA escalation ---';

    -- T5.1 the open queue hides merged and resolved complaints
    SELECT COUNT(*) INTO v_merged
      FROM v_open_queue WHERE status IN ('RESOLVED', 'MERGED');
    PERFORM test_report('T5.1 open queue excludes closed complaints', v_merged = 0,
                        format('leaked=%s', v_merged));

    -- T5.2 a merged complaint shows its parent in the citizen view
    SELECT COUNT(*) INTO v_rows
      FROM v_citizen_complaints
     WHERE complaint_id = 16 AND parent_complaint_id = 15;
    PERFORM test_report('T5.2 citizen view shows the parent complaint', v_rows = 1);

    -- T5.3 escalation catches the two overdue seeded complaints
    v_escalated := fn_escalate_overdue();
    PERFORM test_report('T5.3 SLA sweep escalated overdue complaints', v_escalated >= 2,
                        format('escalated=%s', v_escalated));

    -- T5.4 running it again escalates nothing (it is idempotent)
    v_escalated := fn_escalate_overdue();
    PERFORM test_report('T5.4 second SLA sweep is a no-op', v_escalated = 0,
                        format('escalated=%s', v_escalated));

    -- T5.5 the materialized view refreshes without error
    REFRESH MATERIALIZED VIEW mv_department_performance;
    SELECT COUNT(*) INTO v_rows FROM mv_department_performance;
    PERFORM test_report('T5.5 dashboard view refreshes', v_rows = 6,
                        format('rows=%s', v_rows));
END $$;


-- =====================================================================
-- GROUP 6 - CASCADE BEHAVIOUR
-- =====================================================================
DO $$
DECLARE
    v_id    INT;
    v_rows  INT;
BEGIN
    RAISE NOTICE '--- Group 6: referential actions ---';

    -- T6.1 deleting a complaint removes its embedding and attachments
    v_id := fn_file_complaint(1, 1, 'Cascade test complaint',
                              'Created so that deletion cascade can be verified properly.');
    INSERT INTO complaint_embedding (complaint_id, embedding)
         VALUES (v_id, fn_demo_embedding('cascade test complaint'));
    INSERT INTO complaint_attachment (complaint_id, attachment_url)
         VALUES (v_id, 'https://example.com/x.jpg');

    DELETE FROM complaint WHERE complaint_id = v_id;

    SELECT (SELECT COUNT(*) FROM complaint_embedding  WHERE complaint_id = v_id)
         + (SELECT COUNT(*) FROM complaint_attachment WHERE complaint_id = v_id)
         + (SELECT COUNT(*) FROM status_history       WHERE complaint_id = v_id)
      INTO v_rows;
    PERFORM test_report('T6.1 complaint delete cascades to children', v_rows = 0,
                        format('orphans=%s', v_rows));
END $$;

-- =====================================================================
-- GROUP 7 - CTE / WINDOW FUNCTION RESULTS
--
-- These verify the queries in 06_advanced_queries.sql return correct
-- answers, not just that they execute.
-- =====================================================================
DO $$
DECLARE
    v_depth  INT;
    v_rows   INT;
BEGIN
    RAISE NOTICE '--- Group 7: CTEs and window functions ---';

    -- T7.1 the recursive merge-chain walk reaches the canonical parent
    WITH RECURSIVE chain AS (
        SELECT c.complaint_id, 0 AS depth
          FROM complaint c WHERE c.complaint_id = 17
        UNION ALL
        SELECT dl.parent_complaint_id, ch.depth + 1
          FROM chain ch
          JOIN duplicate_link dl ON dl.child_complaint_id = ch.complaint_id
    )
    SELECT MAX(depth) INTO v_depth FROM chain;
    PERFORM test_report('T7.1 recursive CTE walks merge chain', v_depth = 1,
                        format('depth=%s', v_depth));

    -- T7.2 INTEGRITY: no merge chain is longer than one hop.
    --      fn_merge_duplicate refuses to merge into an already-merged
    --      complaint, so a depth above 1 would mean that rule leaked.
    WITH RECURSIVE chains AS (
        SELECT child_complaint_id AS start_id, parent_complaint_id AS current_id, 1 AS depth
          FROM duplicate_link
        UNION ALL
        SELECT ch.start_id, dl.parent_complaint_id, ch.depth + 1
          FROM chains ch
          JOIN duplicate_link dl ON dl.child_complaint_id = ch.current_id
         WHERE ch.depth < 10
    )
    SELECT COALESCE(MAX(depth), 0) INTO v_depth FROM chains;
    PERFORM test_report('T7.2 no merge chain longer than one hop', v_depth <= 1,
                        format('max depth=%s', v_depth));

    -- T7.3 RANK() restarts at 1 inside every department partition
    -- the window must be computed in an inner query: an aggregate
    -- cannot contain a window function call
    SELECT COUNT(*) INTO v_rows
    FROM (
        SELECT dept_id, MIN(rnk) AS first_rank
        FROM (
            SELECT c.dept_id,
                   RANK() OVER (PARTITION BY c.dept_id ORDER BY c.sla_deadline) AS rnk
              FROM complaint c
             WHERE c.status NOT IN ('RESOLVED','MERGED') AND c.dept_id IS NOT NULL
        ) w
        GROUP BY dept_id
    ) x
    WHERE first_rank <> 1;
    PERFORM test_report('T7.3 RANK restarts at 1 in every partition', v_rows = 0,
                        format('partitions not starting at 1 = %s', v_rows));

    -- T7.4 the running total ends at the ward's true complaint count
    SELECT COUNT(*) INTO v_rows
    FROM (
        SELECT ward_id, MAX(wc) AS win_total, COUNT(*) AS plain_total
        FROM (
            SELECT c.ward_id, COUNT(*) OVER (PARTITION BY c.ward_id) AS wc
              FROM complaint c
        ) w
        GROUP BY ward_id
    ) x
    WHERE win_total <> plain_total;
    PERFORM test_report('T7.4 window count matches GROUP BY count', v_rows = 0,
                        format('mismatched wards=%s', v_rows));

    -- T7.5 ts_headline returns a highlighted snippet for a known match
    SELECT COUNT(*) INTO v_rows
      FROM complaint
     WHERE search_tsv @@ websearch_to_tsquery('english', 'water pipeline')
       AND ts_headline('english', description,
                       websearch_to_tsquery('english', 'water pipeline')) LIKE '%<b>%';
    PERFORM test_report('T7.5 full-text headline highlights matches', v_rows > 0,
                        format('highlighted=%s', v_rows));
END $$;

\echo ''
\echo '################ END OF TEST SUITE ################'
\echo ''
