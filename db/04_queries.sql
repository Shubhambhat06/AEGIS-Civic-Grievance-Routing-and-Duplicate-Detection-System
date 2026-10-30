-- =====================================================================
-- AEGIS - File 4 of 5 : IMPORTANT QUERIES
--
-- The queries the application actually runs, collected in one place for
-- the report and the demonstration. Each one is numbered and labelled
-- with the SQL features it demonstrates.
--
-- Run as: psql -U postgres -d aegis -f db/04_queries.sql
-- =====================================================================

\echo ''
\echo '=== Q1. Staff work queue, most urgent first ==================='
-- Features: VIEW, ORDER BY, WHERE
-- Used by: /staff dashboard
SELECT complaint_id, title, dept_name, priority, hours_remaining, is_breached
FROM v_open_queue
ORDER BY is_breached DESC, hours_remaining ASC
LIMIT 10;


\echo ''
\echo '=== Q2. Complaints per department with resolution stats ======='
-- Features: JOIN, GROUP BY, aggregate functions, FILTER, LEFT JOIN
-- Used by: /admin dashboard
SELECT d.dept_name,
       COUNT(c.complaint_id)                          AS total,
       COUNT(*) FILTER (WHERE c.status = 'RESOLVED')  AS resolved,
       COUNT(*) FILTER (WHERE c.status = 'ESCALATED') AS escalated,
       ROUND(AVG(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0)::NUMERIC, 1)
                                                      AS avg_hours_to_resolve
FROM department d
LEFT JOIN complaint c ON c.dept_id = d.dept_id
GROUP BY d.dept_name
ORDER BY total DESC;


\echo ''
\echo '=== Q3. Departments slower than the overall average =========='
-- Features: GROUP BY, HAVING, scalar SUBQUERY, aggregate
-- Shows HAVING filtering groups, and a subquery supplying the threshold.
SELECT d.dept_name,
       ROUND(AVG(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0)::NUMERIC, 1)
           AS avg_hours
FROM department d
JOIN complaint c ON c.dept_id = d.dept_id
WHERE c.resolved_at IS NOT NULL
GROUP BY d.dept_name
HAVING AVG(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0) >
       (SELECT AVG(EXTRACT(EPOCH FROM (resolved_at - filed_at))/3600.0)
          FROM complaint WHERE resolved_at IS NOT NULL)
ORDER BY avg_hours DESC;


\echo ''
\echo '=== Q4. Most-duplicated complaints (the headline feature) ====='
-- Features: JOIN, GROUP BY, HAVING, COUNT
-- "This issue has been reported N times" on the staff queue.
SELECT p.complaint_id,
       p.title,
       w.ward_name,
       COUNT(dl.child_complaint_id) AS times_reported_again
FROM complaint p
JOIN ward           w  ON w.ward_id = p.ward_id
JOIN duplicate_link dl ON dl.parent_complaint_id = p.complaint_id
GROUP BY p.complaint_id, p.title, w.ward_name
HAVING COUNT(dl.child_complaint_id) >= 1
ORDER BY times_reported_again DESC;


\echo ''
\echo '=== Q5. Citizens who filed more than one complaint ==========='
-- Features: JOIN, GROUP BY, HAVING, ORDER BY
SELECT ct.full_name, ct.email, w.ward_name, COUNT(c.complaint_id) AS complaints_filed
FROM citizen ct
JOIN ward      w ON w.ward_id = ct.ward_id
JOIN complaint c ON c.citizen_id = ct.citizen_id
GROUP BY ct.citizen_id, ct.full_name, ct.email, w.ward_name
HAVING COUNT(c.complaint_id) > 1
ORDER BY complaints_filed DESC, ct.full_name;


\echo ''
\echo '=== Q6. Wards with above-average complaint volume ============'
-- Features: correlated-free subquery in HAVING, GROUP BY, aggregate
SELECT w.ward_name, w.zone, COUNT(c.complaint_id) AS complaint_count
FROM ward w
JOIN complaint c ON c.ward_id = w.ward_id
GROUP BY w.ward_id, w.ward_name, w.zone
HAVING COUNT(c.complaint_id) > (
    SELECT AVG(cnt) FROM (
        SELECT COUNT(*) AS cnt FROM complaint GROUP BY ward_id
    ) AS per_ward
)
ORDER BY complaint_count DESC;


\echo ''
\echo '=== Q7. Staff workload: open items per staff member =========='
-- Features: LEFT JOIN, GROUP BY, FILTER, COALESCE
SELECT s.full_name,
       d.dept_name,
       s.role,
       COUNT(c.complaint_id) FILTER (WHERE c.status IN ('ROUTED','IN_PROGRESS','ESCALATED'))
           AS open_items,
       COUNT(c.complaint_id) FILTER (WHERE c.status = 'RESOLVED')
           AS resolved_items
FROM staff s
JOIN department d ON d.dept_id = s.dept_id
LEFT JOIN complaint c ON c.assigned_staff_id = s.staff_id
GROUP BY s.staff_id, s.full_name, d.dept_name, s.role
ORDER BY open_items DESC, s.full_name;


\echo ''
\echo '=== Q8. Full-text keyword search =============================='
-- Features: FULL-TEXT SEARCH (GIN index on the generated tsvector)
-- Used by: the search box on the citizen portal.
SELECT complaint_id,
       title,
       ROUND(ts_rank(search_tsv, websearch_to_tsquery('english', 'pothole road'))::NUMERIC, 4) AS rank
FROM complaint
WHERE search_tsv @@ websearch_to_tsquery('english', 'pothole road')
ORDER BY rank DESC
LIMIT 5;


\echo ''
\echo '=== Q9. Vector similarity search: find duplicates of #18 ====='
-- Features: VECTOR SIMILARITY SEARCH via the stored function
SELECT * FROM fn_find_duplicates(18, 0.30, 5);


\echo ''
\echo '=== Q10. Full audit trail for one complaint =================='
-- Features: JOIN, ORDER BY, COALESCE on a nullable FK
SELECT sh.changed_at,
       COALESCE(sh.old_status::TEXT, '(new)') AS from_status,
       sh.new_status                          AS to_status,
       COALESCE(s.full_name, 'system')        AS changed_by,
       sh.remarks
FROM status_history sh
LEFT JOIN staff s ON s.staff_id = sh.changed_by
WHERE sh.complaint_id = 15
ORDER BY sh.changed_at;


\echo ''
\echo '=== Q11. Citizen satisfaction by department =================='
-- Features: multi-table JOIN, AVG, COUNT, GROUP BY, ORDER BY
SELECT d.dept_name,
       COUNT(f.complaint_id)            AS ratings_received,
       ROUND(AVG(f.rating)::NUMERIC, 2) AS avg_rating
FROM department d
JOIN complaint c ON c.dept_id      = d.dept_id
JOIN feedback  f ON f.complaint_id = c.complaint_id
GROUP BY d.dept_name
ORDER BY avg_rating DESC;


\echo ''
\echo '=== Q12. Complaints with no feedback (NOT EXISTS subquery) ==='
-- Features: correlated SUBQUERY with NOT EXISTS
SELECT c.complaint_id, c.title, c.resolved_at
FROM complaint c
WHERE c.status = 'RESOLVED'
  AND NOT EXISTS (
        SELECT 1 FROM feedback f WHERE f.complaint_id = c.complaint_id
      )
ORDER BY c.resolved_at DESC;


\echo ''
\echo '=== Q13. Citizens with multiple phone numbers ================'
-- Features: JOIN on the multivalued-attribute table, GROUP BY, HAVING,
--           string_agg
SELECT ct.full_name,
       COUNT(cp.phone)              AS phone_count,
       string_agg(cp.phone, ', ')   AS numbers
FROM citizen ct
JOIN citizen_phone cp ON cp.citizen_id = ct.citizen_id
GROUP BY ct.citizen_id, ct.full_name
HAVING COUNT(cp.phone) > 1;


\echo ''
\echo '=== Q14. Department performance dashboard (materialized view) ='
-- Features: MATERIALIZED VIEW
SELECT dept_name, total_complaints, resolved_count, open_count,
       avg_resolution_hours, sla_breach_pct
FROM mv_department_performance
ORDER BY total_complaints DESC;


\echo ''
\echo '=== Q15. Index usage proof for the SLA sweep ================='
-- Features: EXPLAIN against the PARTIAL INDEX idx_complaint_sla_open
EXPLAIN (COSTS OFF)
SELECT complaint_id FROM complaint
WHERE status NOT IN ('RESOLVED','MERGED') AND sla_deadline < now();
