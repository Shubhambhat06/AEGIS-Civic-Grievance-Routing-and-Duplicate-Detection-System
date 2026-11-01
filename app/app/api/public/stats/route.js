// =====================================================================
// GET /api/public/stats  -  headline figures for the public landing page
//
// No sign-in required. Returns aggregate counts only: no names, no
// complaint text, nothing that identifies a citizen.
// =====================================================================
import { NextResponse } from 'next/server';
import { query } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function GET() {
  const [totals] = await query(
    `SELECT COUNT(*)::INT                                                     AS received,
            COUNT(*) FILTER (WHERE status = 'RESOLVED')::INT                  AS resolved,
            COUNT(*) FILTER (WHERE status = 'MERGED')::INT                    AS merged,
            COUNT(*) FILTER (WHERE status NOT IN ('RESOLVED','MERGED'))::INT  AS open,
            ROUND(AVG(EXTRACT(EPOCH FROM (resolved_at - filed_at)) / 3600.0)
                  FILTER (WHERE resolved_at IS NOT NULL))::INT                AS avg_hours
       FROM complaint`
  );
  const [counts] = await query(
    `SELECT (SELECT COUNT(*) FROM department)::INT AS departments,
            (SELECT COUNT(*) FROM ward)::INT       AS wards`
  );
  return NextResponse.json({ ...totals, ...counts });
}
