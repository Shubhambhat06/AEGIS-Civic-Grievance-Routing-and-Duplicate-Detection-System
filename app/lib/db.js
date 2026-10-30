// =====================================================================
// Database connection pool.
//
// Requirement 10 of the project specification: credentials must NOT be
// hard-coded. Everything here comes from environment variables, which
// are read from .env.local (git-ignored). See .env.example.
// =====================================================================
import { Pool } from 'pg';

if (!process.env.DATABASE_URL) {
  throw new Error(
    'DATABASE_URL is not set. Copy .env.example to .env.local and fill it in.'
  );
}

// Next.js reloads modules during development, which would otherwise
// create a new pool on every edit and exhaust the server's connections.
// Caching the pool on globalThis keeps exactly one pool per process.
const globalForPg = globalThis;

export const pool =
  globalForPg._aegisPool ??
  new Pool({
    connectionString: process.env.DATABASE_URL,
    max: Number(process.env.PGPOOL_MAX ?? 10),
    idleTimeoutMillis: 30000,
  });

if (process.env.NODE_ENV !== 'production') {
  globalForPg._aegisPool = pool;
}

/**
 * Run a parameterised query.
 *
 * Always pass values through `params` - never build SQL by string
 * concatenation. The pg driver sends parameters separately from the
 * statement, which is what makes SQL injection impossible here.
 */
export async function query(text, params = []) {
  const result = await pool.query(text, params);
  return result.rows;
}

/**
 * Run several statements inside one transaction.
 * If the callback throws, everything is rolled back.
 */
export async function withTransaction(callback) {
  const client = await pool.connect();
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
