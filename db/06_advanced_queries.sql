-- =====================================================================
-- AEGIS - File 6 of 6 : CTEs, WINDOW FUNCTIONS AND FULL-TEXT SEARCH
--
-- These map directly onto Unit 2 of the course syllabus:
--   "Nested Subqueries, Correlated queries, Join expressions, Views,
--    Triggers, Functions, Procedures, CTE, window functions and
--    full text search functions."
--
-- Kept in a separate file from 04_queries.sql so that the numbering of
-- the application queries stays stable.
--
-- Run as: psql -U postgres -d aegis -f db/06_advanced_queries.sql
-- =====================================================================


\echo ''
\echo '=== W1. Rank complaints by urgency WITHIN each department ====='
-- Window function: RANK() OVER (PARTITION BY ... ORDER BY ...)
--
-- Every department gets its own ranking restarting at 1. A plain
-- ORDER BY would give one global list; PARTITION BY restarts the
-- numbering per department, which is what the staff queue needs.
SELECT d.dept_name,
       c.complaint_id,
       c.title,
       c.priority,
       c.sla_deadline,
       RANK() OVER (PARTITION BY c.dept_id ORDER BY c.sla_deadline) AS urgency_rank
FROM complaint c
JOIN department d ON d.dept_id = c.dept_id
WHERE c.status NOT IN ('RESOLVED', 'MERGED')
ORDER BY d.dept_name, urgency_rank;


\echo ''
\echo '=== W2. Each department vs its own average (window aggregate) ='
-- Window function used as an AGGREGATE without collapsing rows.
--
-- AVG(...) OVER (PARTITION BY dept_id) computes the departmental
-- average but keeps every individual row visible beside it, which a
-- GROUP BY cannot do.
SELECT d.dept_name,
       c.complaint_id,
       ROUND(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0) AS hours_taken,
       ROUND(AVG(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0)
             OVER (PARTITION BY c.dept_id)) AS dept_avg_hours,
       ROUND(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0
             - AVG(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0)
               OVER (PARTITION BY c.dept_id)) AS difference
FROM complaint c
JOIN department d ON d.dept_id = c.dept_id
WHERE c.resolved_at IS NOT NULL
ORDER BY d.dept_name, difference DESC;


\echo ''
\echo '=== W3. Running total of complaints per ward over time ========'
-- Window functions: SUM(...) OVER (PARTITION BY ... ORDER BY ...)
--                   and ROW_NUMBER()
--
-- The ORDER BY inside OVER makes this a *running* total: each row sums
-- itself and everything before it within its ward.
SELECT w.ward_name,
       c.filed_at::DATE AS filed_on,
       c.complaint_id,
       ROW_NUMBER() OVER (PARTITION BY c.ward_id ORDER BY c.filed_at) AS nth_in_ward,
       COUNT(*)     OVER (PARTITION BY c.ward_id ORDER BY c.filed_at
                          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           AS running_total
FROM complaint c
JOIN ward w ON w.ward_id = c.ward_id
ORDER BY w.ward_name, c.filed_at;


\echo ''
\echo '=== W4. Gap between consecutive complaints (LAG) =============='
-- Window functions: LAG() and LEAD()
--
-- Looks at the previous row within the same ward to measure how much
-- time passed between reports. A sudden cluster of short gaps is what
-- a repeated issue looks like in the data.
SELECT w.ward_name,
       c.complaint_id,
       c.title,
       c.filed_at,
       LAG(c.filed_at) OVER (PARTITION BY c.ward_id ORDER BY c.filed_at)
           AS previous_complaint_at,
       ROUND(EXTRACT(EPOCH FROM (
           c.filed_at - LAG(c.filed_at) OVER (PARTITION BY c.ward_id ORDER BY c.filed_at)
       ))/3600.0, 1) AS hours_since_previous
FROM complaint c
JOIN ward w ON w.ward_id = c.ward_id
ORDER BY w.ward_name, c.filed_at;


\echo ''
\echo '=== W5. Top 2 slowest complaints per department (CTE + window) '
-- CTE feeding a window function, then filtered in the outer query.
--
-- This is the standard "top N per group" pattern. It needs two steps
-- because a window function cannot appear in a WHERE clause: the
-- ranking is computed in the CTE, and the outer query filters on it.
WITH ranked AS (
    SELECT c.complaint_id,
           c.title,
           d.dept_name,
           EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0 AS hours_taken,
           DENSE_RANK() OVER (
               PARTITION BY c.dept_id
               ORDER BY (c.resolved_at - c.filed_at) DESC
           ) AS slowness_rank
    FROM complaint c
    JOIN department d ON d.dept_id = c.dept_id
    WHERE c.resolved_at IS NOT NULL
)
SELECT dept_name, complaint_id, title, ROUND(hours_taken) AS hours_taken, slowness_rank
FROM ranked
WHERE slowness_rank <= 2
ORDER BY dept_name, slowness_rank;


\echo ''
\echo '=== W6. Ward workload summary (multiple CTEs) ================='
-- Several CTEs combined in one statement.
--
-- Each CTE answers one simple question; the final SELECT joins them.
-- Written as nested subqueries this would be almost unreadable, which
-- is the main practical argument for CTEs.
WITH filed AS (
    SELECT ward_id, COUNT(*) AS total_filed
    FROM complaint
    GROUP BY ward_id
),
resolved AS (
    SELECT ward_id, COUNT(*) AS total_resolved
    FROM complaint
    WHERE status = 'RESOLVED'
    GROUP BY ward_id
),
duplicates AS (
    SELECT c.ward_id, COUNT(*) AS total_merged
    FROM complaint c
    JOIN duplicate_link dl ON dl.child_complaint_id = c.complaint_id
    GROUP BY c.ward_id
)
SELECT w.ward_name,
       w.zone,
       COALESCE(f.total_filed, 0)    AS filed,
       COALESCE(r.total_resolved, 0) AS resolved,
       COALESCE(dp.total_merged, 0)  AS merged_as_duplicate,
       ROUND(100.0 * COALESCE(dp.total_merged, 0)
             / NULLIF(f.total_filed, 0), 1) AS duplicate_pct
FROM ward w
LEFT JOIN filed      f  ON f.ward_id  = w.ward_id
LEFT JOIN resolved   r  ON r.ward_id  = w.ward_id
LEFT JOIN duplicates dp ON dp.ward_id = w.ward_id
ORDER BY filed DESC;


\echo ''
\echo '=== W7. Follow a merge chain (RECURSIVE CTE) =================='
-- WITH RECURSIVE.
--
-- A duplicate points at its parent, and in principle that parent could
-- itself have been merged earlier. This walks the chain upward from a
-- given complaint until it reaches the canonical one.
--
-- fn_merge_duplicate forbids merging into an already-merged complaint,
-- so in practice these chains are one hop. The recursive query is what
-- PROVES that: if it ever returns a depth greater than 1, the rule has
-- been violated somewhere.
WITH RECURSIVE chain AS (
    -- anchor: start at the complaint we were asked about
    SELECT c.complaint_id,
           c.title,
           c.status,
           0 AS depth
    FROM complaint c
    WHERE c.complaint_id = 17

    UNION ALL

    -- recursive step: hop to the parent, if there is one
    SELECT p.complaint_id,
           p.title,
           p.status,
           ch.depth + 1
    FROM chain ch
    JOIN duplicate_link dl ON dl.child_complaint_id = ch.complaint_id
    JOIN complaint      p  ON p.complaint_id        = dl.parent_complaint_id
)
SELECT depth, complaint_id, title, status FROM chain ORDER BY depth;


\echo ''
\echo '=== W8. Deepest merge chain in the whole table (RECURSIVE) ===='
-- Same technique applied as a data-integrity check across every
-- complaint, not just one. Expected maximum depth is 1.
WITH RECURSIVE chains AS (
    SELECT child_complaint_id AS start_id,
           parent_complaint_id AS current_id,
           1 AS depth
    FROM duplicate_link

    UNION ALL

    SELECT ch.start_id,
           dl.parent_complaint_id,
           ch.depth + 1
    FROM chains ch
    JOIN duplicate_link dl ON dl.child_complaint_id = ch.current_id
    WHERE ch.depth < 10          -- safety stop against a cycle
)
SELECT MAX(depth) AS deepest_merge_chain,
       COUNT(*)   AS total_chain_steps
FROM chains;


\echo ''
\echo '=== W9. Full-text search with ranking and highlighting ========'
-- Full-text search functions: websearch_to_tsquery, ts_rank, ts_headline
--
-- ts_headline returns the matching fragment with the search terms
-- marked, which is what a search-results page shows under each hit.
SELECT c.complaint_id,
       c.title,
       ROUND(ts_rank(c.search_tsv,
                     websearch_to_tsquery('english', 'water pipeline'))::NUMERIC, 4) AS rank,
       ts_headline('english', c.description,
                   websearch_to_tsquery('english', 'water pipeline'),
                   'StartSel=[, StopSel=], MaxWords=18, MinWords=6') AS snippet
FROM complaint c
WHERE c.search_tsv @@ websearch_to_tsquery('english', 'water pipeline')
ORDER BY rank DESC
LIMIT 5;


\echo ''
\echo '=== W10. Combining it all: department scorecard ==============='
-- CTE + window function + aggregate + full outer context.
--
-- NTILE(4) splits departments into quartiles by resolution speed, and
-- the percentage-of-total column uses a window SUM over the whole
-- result rather than a second query.
WITH dept_stats AS (
    SELECT d.dept_id,
           d.dept_name,
           COUNT(c.complaint_id) AS total,
           AVG(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at))/3600.0) AS avg_hours
    FROM department d
    LEFT JOIN complaint c ON c.dept_id = d.dept_id
    GROUP BY d.dept_id, d.dept_name
)
SELECT dept_name,
       total,
       ROUND(avg_hours) AS avg_hours,
       ROUND(100.0 * total / SUM(total) OVER (), 1) AS pct_of_all_complaints,
       NTILE(4) OVER (ORDER BY avg_hours NULLS LAST) AS speed_quartile
FROM dept_stats
ORDER BY total DESC;
