-- =====================================================================
-- AEGIS - demo embedding pipeline (SQL only)
--
-- This is the psql-only stand-in for scripts/embed.py. It finds every
-- complaint that does not yet have an embedding and generates one with
-- fn_demo_embedding.
--
-- Why it exists: filing a complaint through the web interface inserts
-- the complaint row only. Embedding is a separate, asynchronous step,
-- exactly as it would be in production. Running this file is what
-- "the pipeline ran" means when you are demonstrating without Python.
--
-- Inserting into complaint_embedding fires t_embedding_auto_route, so
-- any complaint that was still unrouted gets a department as a result.
--
-- Run as: psql -U postgres -d aegis -f scripts/embed_demo.sql
-- Docker: docker compose exec db psql -U aegis -d aegis -f /aegis-sql/../scripts/embed_demo.sql
--         (or see README for the simpler copy-paste form)
-- =====================================================================

INSERT INTO complaint_embedding (complaint_id, embedding, model_name)
SELECT c.complaint_id,
       fn_demo_embedding(c.title || ' ' || c.description),
       'demo-hashing-384'
FROM complaint c
WHERE NOT EXISTS (
    SELECT 1 FROM complaint_embedding e WHERE e.complaint_id = c.complaint_id
)
ORDER BY c.complaint_id;

-- Report what happened.
SELECT c.complaint_id,
       left(c.title, 40) AS title,
       c.status,
       COALESCE(d.dept_name, '(unrouted)') AS routed_to
FROM complaint c
LEFT JOIN department d ON d.dept_id = c.dept_id
WHERE c.filed_at > now() - interval '1 hour'
ORDER BY c.complaint_id;
