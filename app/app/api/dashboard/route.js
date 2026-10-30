// GET /api/dashboard  -  admin statistics
// Reads the materialized view (advanced feature: views).
import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { requireRole } from '@/lib/auth';

export async function GET() {
  const auth = await requireRole(['ADMIN']);   // admins only
  if (auth.error) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const departments = await query(
    `SELECT dept_name, total_complaints, resolved_count, open_count,
            escalated_count, avg_resolution_hours, sla_breach_pct
       FROM mv_department_performance
      ORDER BY total_complaints DESC`
  );

  const wards = await query(
    `SELECT w.ward_name, COUNT(c.complaint_id) AS complaint_count
       FROM ward w
       LEFT JOIN complaint c ON c.ward_id = w.ward_id
      GROUP BY w.ward_id, w.ward_name
      ORDER BY complaint_count DESC`
  );

  const duplicates = await query(
    `SELECT p.complaint_id, p.title, COUNT(dl.child_complaint_id) AS merged_count
       FROM complaint p
       JOIN duplicate_link dl ON dl.parent_complaint_id = p.complaint_id
      GROUP BY p.complaint_id, p.title
     HAVING COUNT(dl.child_complaint_id) >= 1
      ORDER BY merged_count DESC
      LIMIT 10`
  );

  return NextResponse.json({ departments, wards, duplicates });
}
