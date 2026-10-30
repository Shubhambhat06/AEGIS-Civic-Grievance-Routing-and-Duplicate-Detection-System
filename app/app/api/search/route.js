// GET /api/search?q=...  -  full-text search over complaints
// Uses the GIN index on complaint.search_tsv (advanced feature: FTS).
import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { requireRole } from '@/lib/auth';

export async function GET(request) {
  const auth = await requireRole();
  if (auth.error) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const q = request.nextUrl.searchParams.get('q')?.trim();
  if (!q) return NextResponse.json({ results: [] });

  const results = await query(
    `SELECT c.complaint_id, c.title, c.status, w.ward_name,
            ts_rank(c.search_tsv, websearch_to_tsquery('english', $1)) AS rank
       FROM complaint c
       JOIN ward w ON w.ward_id = c.ward_id
      WHERE c.search_tsv @@ websearch_to_tsquery('english', $1)
      ORDER BY rank DESC
      LIMIT 20`,
    [q]
  );

  return NextResponse.json({ results });
}
