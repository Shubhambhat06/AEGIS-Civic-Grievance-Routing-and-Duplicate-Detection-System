// POST /api/admin/escalate  -  run the SLA sweep now (admin only)
// In production fn_escalate_overdue runs on a schedule; this lets an
// administrator trigger it on demand and see the result.
import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { requireRole } from '@/lib/auth';

export async function POST() {
  const auth = await requireRole(['ADMIN']);
  if (auth.error) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const [row] = await query(`SELECT fn_escalate_overdue() AS escalated`);
  return NextResponse.json({ escalated: row.escalated });
}
