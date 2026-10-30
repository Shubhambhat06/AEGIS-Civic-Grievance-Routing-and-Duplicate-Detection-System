#!/usr/bin/env python3
"""
AEGIS embedding pipeline.

Reads complaints that do not yet have an embedding, converts their text
into a 384-dimension vector, and writes it to complaint_embedding.
Inserting that row fires the auto-routing trigger, so a complaint gets
its department assigned as a side effect of being embedded.

Which data is embedded:
    title + ' ' + description, i.e. everything the citizen typed.

Which model:
    sentence-transformers/all-MiniLM-L6-v2 - 384 dimensions, small
    enough to run on CPU, and trained for sentence similarity, which is
    exactly the comparison we need.

How vectors are stored:
    PostgreSQL VECTOR(384) column, indexed with HNSW.

Similarity metric:
    cosine distance (the <=> operator). Embeddings are L2-normalised by
    the model, so cosine is the natural choice and similarity is simply
    1 - distance.

Usage:
    pip install -r scripts/requirements.txt
    export DATABASE_URL=postgresql://user:pass@localhost:5432/aegis
    python3 scripts/embed.py              # embed everything missing
    python3 scripts/embed.py --recompute  # re-embed all complaints
"""

import argparse
import os
import sys

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
DIMENSIONS = 384
BATCH_SIZE = 64


def connect():
    url = os.environ.get("DATABASE_URL")
    if not url:
        sys.exit("DATABASE_URL is not set. See app/.env.example.")
    try:
        import psycopg2
    except ImportError:
        sys.exit("psycopg2 is not installed. Run: pip install -r scripts/requirements.txt")
    return psycopg2.connect(url)


def load_model():
    try:
        from sentence_transformers import SentenceTransformer
    except ImportError:
        sys.exit(
            "sentence-transformers is not installed.\n"
            "Run: pip install -r scripts/requirements.txt\n"
            "(Or demonstrate without it: db/03_seed.sql defines "
            "fn_demo_embedding, a simpler SQL-only fallback.)"
        )
    print(f"Loading {MODEL_NAME} ...")
    return SentenceTransformer(MODEL_NAME)


def fetch_pending(conn, recompute):
    """Return [(complaint_id, text), ...] for complaints needing an embedding."""
    where = "" if recompute else """
        WHERE NOT EXISTS (
            SELECT 1 FROM complaint_embedding e
             WHERE e.complaint_id = c.complaint_id
        )"""
    with conn.cursor() as cur:
        cur.execute(
            f"""SELECT c.complaint_id, c.title || ' ' || c.description
                  FROM complaint c
                  {where}
                 ORDER BY c.complaint_id"""
        )
        return cur.fetchall()


def store(conn, complaint_id, vector):
    """Upsert one embedding. The vector is sent as pgvector's text form."""
    literal = "[" + ",".join(f"{v:.6f}" for v in vector) + "]"
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO complaint_embedding (complaint_id, embedding, model_name)
                    VALUES (%s, %s::vector, %s)
               ON CONFLICT (complaint_id)
                 DO UPDATE SET embedding    = EXCLUDED.embedding,
                               model_name   = EXCLUDED.model_name,
                               generated_at = now()""",
            (complaint_id, literal, MODEL_NAME.split("/")[-1]),
        )


def main():
    parser = argparse.ArgumentParser(description="Generate complaint embeddings.")
    parser.add_argument(
        "--recompute",
        action="store_true",
        help="re-embed every complaint, not just the ones without an embedding",
    )
    args = parser.parse_args()

    conn = connect()
    pending = fetch_pending(conn, args.recompute)

    if not pending:
        print("Nothing to embed. All complaints already have embeddings.")
        return

    print(f"{len(pending)} complaint(s) to embed.")
    model = load_model()

    for start in range(0, len(pending), BATCH_SIZE):
        batch = pending[start : start + BATCH_SIZE]
        texts = [text for _, text in batch]

        # normalize_embeddings=True gives unit vectors, so cosine
        # distance in PostgreSQL behaves exactly as the model intends.
        vectors = model.encode(texts, normalize_embeddings=True, show_progress_bar=False)

        for (complaint_id, _), vector in zip(batch, vectors):
            if len(vector) != DIMENSIONS:
                sys.exit(f"Model returned {len(vector)} dimensions, expected {DIMENSIONS}.")
            store(conn, complaint_id, vector)

        conn.commit()
        print(f"  embedded {min(start + BATCH_SIZE, len(pending))}/{len(pending)}")

    conn.close()
    print("Done. Auto-routing ran for any complaint that was still unrouted.")


if __name__ == "__main__":
    main()
