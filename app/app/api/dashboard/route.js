// =====================================================================
// GET /api/dashboard  -  statistics for the admin dashboard (admin only)
// =====================================================================
import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { requireRole } from '@/lib/auth';

export async function GET() {
  const auth = await requireRole(['ADMIN']);   // admins only
  if (auth.error) return NextResponse.json({ error: auth.error }, { status: auth.status });

  // The materialized view is cheap to rebuild at this scale, so refresh
  // it on read: the dashboard should reflect merges made a moment ago.
  // CONCURRENTLY keeps it readable during the refresh.
  await query(`REFRESH MATERIALIZED VIEW CONCURRENTLY mv_department_performance`);

  const departments = await query(
    `SELECT dept_name, total_complaints, resolved_count, open_count,
            escalated_count, avg_resolution_hours, sla_breach_pct
       FROM mv_department_performance
      ORDER BY total_complaints DESC, dept_name`
  );

  // Average time to resolve against each department's own SLA target.
  const sla = await query(
    `SELECT d.dept_name,
            d.default_sla_hours,
            ROUND(AVG(EXTRACT(EPOCH FROM (c.resolved_at - c.filed_at)) / 3600.0))::INT AS avg_hours,
            COUNT(c.complaint_id)::INT AS resolved
       FROM department d
       LEFT JOIN complaint c ON c.dept_id = d.dept_id AND c.resolved_at IS NOT NULL
      GROUP BY d.dept_id, d.dept_name, d.default_sla_hours
      ORDER BY d.dept_name`
  );

  const statuses = await query(
    `SELECT status::TEXT AS status, COUNT(*)::INT AS n
       FROM complaint
      GROUP BY status`
  );

  // Complaints received per week over the last 13 weeks. generate_series
  // supplies every week, so weeks with no complaints still appear as 0.
  const weekly = await query(
    `SELECT to_char(w.week_start, 'DD Mon') AS label,
            COUNT(c.complaint_id)::INT       AS n
       FROM generate_series(
              date_trunc('week', now()) - interval '12 weeks',
              date_trunc('week', now()),
              interval '1 week') AS w(week_start)
       LEFT JOIN complaint c ON date_trunc('week', c.filed_at) = w.week_start
      GROUP BY w.week_start
      ORDER BY w.week_start`
  );

  const wards = await query(
    `SELECT w.ward_name, w.zone, COUNT(c.complaint_id)::INT AS complaint_count
       FROM ward w
       LEFT JOIN complaint c ON c.ward_id = w.ward_id
      GROUP BY w.ward_id, w.ward_name, w.zone
      ORDER BY complaint_count DESC, w.ward_name`
  );

  const duplicates = await query(
    `SELECT p.complaint_id, p.title, w.ward_name, p.status::TEXT AS status,
            COUNT(dl.child_complaint_id)::INT AS merged_count
       FROM complaint p
       JOIN ward w            ON w.ward_id = p.ward_id
       JOIN duplicate_link dl ON dl.parent_complaint_id = p.complaint_id
      GROUP BY p.complaint_id, p.title, w.ward_name, p.status
     HAVING COUNT(dl.child_complaint_id) >= 1
      ORDER BY merged_count DESC
      LIMIT 10`
  );

  const [totals] = await query(
    `SELECT COUNT(*)::INT AS received,
            COUNT(*) FILTER (WHERE status NOT IN ('RESOLVED','MERGED'))::INT AS open,
            COUNT(*) FILTER (WHERE status = 'RESOLVED')::INT                 AS resolved,
            COUNT(*) FILTER (WHERE status = 'MERGED')::INT                   AS merged,
            COUNT(*) FILTER (WHERE status NOT IN ('RESOLVED','MERGED')
                               AND sla_deadline < now())::INT                AS overdue
       FROM complaint`
  );

  return NextResponse.json({ totals, departments, sla, statuses, weekly, wards, duplicates });
}
