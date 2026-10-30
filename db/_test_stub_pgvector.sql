-- =====================================================================
-- TEST-ONLY SHIM. Not part of the deliverable schema.
--
-- The grading/dev machine runs PostgreSQL with pgvector installed, so
-- 01_schema.sql uses VECTOR(384) and the <=> cosine-distance operator
-- directly. This file lets the SQL be executed and verified on a plain
-- PostgreSQL build that has no pgvector, by re-implementing the one
-- operator the project uses on top of REAL[].
--
-- Do NOT run this against the real database.
-- =====================================================================

CREATE OR REPLACE FUNCTION test_cosine_distance(a REAL[], b REAL[])
RETURNS FLOAT8
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
DECLARE
    dot FLOAT8 := 0; na FLOAT8 := 0; nb FLOAT8 := 0; i INT;
BEGIN
    IF array_length(a,1) <> array_length(b,1) THEN
        RAISE EXCEPTION 'vector dimension mismatch';
    END IF;
    FOR i IN 1..array_length(a,1) LOOP
        dot := dot + a[i]*b[i];
        na  := na  + a[i]*a[i];
        nb  := nb  + b[i]*b[i];
    END LOOP;
    IF na = 0 OR nb = 0 THEN RETURN 1; END IF;
    RETURN 1 - (dot / (sqrt(na) * sqrt(nb)));
END;
$$;

CREATE OPERATOR <=> (
    LEFTARG  = REAL[],
    RIGHTARG = REAL[],
    FUNCTION = test_cosine_distance
);
