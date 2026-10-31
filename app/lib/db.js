// =====================================================================
// Database connection pool.
//
// Requirement 10 of the project specification: credentials must NOT be
// hard-coded. Everything here comes from environment variables, which
// are read from .env.local in development, or injected by Docker
// Compose when running in a container. See .env.example.
//
// The pool is created LAZILY, on the first query. This matters for the
// Docker build: `next build` runs with no database available, so a pool
// created at module load would make the image build fail.
// =====================================================================
import { Pool } from 'pg';

// Next.js reloads modules during development, which would otherwise
// create a new pool on every edit and exhaust the server's connections.
// Caching the pool on globalThis keeps exactly one pool per process.
const globalForPg = globalThis;

function getPool() {
  if (globalForPg._aegisPool) return globalForPg._aegisPool;

  if (!process.env.DATABASE_URL) {
    throw new Error(
      'DATABASE_URL is not set. Copy .env.example to .env.local and fill it in, ' +
        'or run the stack with docker compose up.'
    );
  }

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    max: Number(process.env.PGPOOL_MAX ?? 10),
    idleTimeoutMillis: 30000,
  });

  globalForPg._aegisPool = pool;
  return pool;
}

/**
 * Run a parameterised query.
 *
 * Always pass values through `params` - never build SQL by string
 * concatenation. The pg driver sends parameters separately from the
 * statement, which is what makes SQL injection impossible here.
 */
export async function query(text, params = []) {
  const result = await getPool().query(text, params);
  return result.rows;
}

/**
 * Run several statements inside one transaction.
 * If the callback throws, everything is rolled back.
 */
export async function withTransaction(callback) {
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export { getPool as pool };
