// =====================================================================
// GET  /api/complaints  -  list complaints (what you see depends on role)
// POST /api/complaints  -  file a new complaint (citizens only)
// =====================================================================
import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { requireRole } from '@/lib/auth';

export async function GET(request) {
  const auth = await requireRole();
  if (auth.error) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { session } = auth;

  // A citizen only ever sees their own complaints. This filter is applied
  // on the server; the client cannot ask for someone else's data.
  if (session.type === 'citizen') {
    const rows = await query(
      `SELECT complaint_id, title, status, filed_at, resolved_at,
              parent_complaint_id, merged_into_title, merged_into_status
         FROM v_citizen_complaints
        WHERE citizen_id = $1
        ORDER BY filed_at DESC`,
      [session.id]
    );
    return NextResponse.json({ complaints: rows });
  }

  // Staff see their department's queue. Admins see everything.
  const onlyMine = request.nextUrl.searchParams.get('mine') === '1';

  const rows = await query(
    `SELECT q.complaint_id, q.title, q.priority, q.status, q.dept_name,
            q.ward_name, q.assigned_to, q.filed_at, q.sla_deadline,
            q.hours_remaining, q.is_breached, q.duplicate_count
       FROM v_open_queue q
       JOIN complaint c ON c.complaint_id = q.complaint_id
      WHERE ($1::INT IS NULL OR c.dept_id = $1)
        AND ($2::BOOLEAN IS FALSE OR c.assigned_staff_id = $3)
      ORDER BY q.is_breached DESC, q.hours_remaining ASC`,
    [session.role === 'ADMIN' ? null : session.deptId, onlyMine, session.id]
  );

  return NextResponse.json({ complaints: rows });
}


export async function POST(request) {
  const auth = await requireRole(['CITIZEN']);
  if (auth.error) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { session } = auth;
  const body = await request.json();
  const { title, description, priority, latitude, longitude } = body;

  // Light validation here for a friendly error message. The real
  // enforcement is the CHECK constraints in the database, which apply
  // no matter how the row is inserted.
  if (!title || title.trim().length < 5) {
    return NextResponse.json({ error: 'Title must be at least 5 characters' }, { status: 400 });
  }
  if (!description || description.trim().length < 15) {
    return NextResponse.json({ error: 'Description must be at least 15 characters' }, { status: 400 });
  }

  try {
    // fn_file_complaint keeps the SLA-deadline rule inside the database.
    const [row] = await query(
      `SELECT fn_file_complaint($1, $2, $3, $4, $5, $6, $7) AS complaint_id`,
      [
        session.id,
        session.wardId,
        title.trim(),
        description.trim(),
        priority || 'MEDIUM',
        latitude ?? null,
        longitude ?? null,
      ]
    );

    return NextResponse.json({ complaintId: row.complaint_id }, { status: 201 });
  } catch (err) {
    // A constraint violation means the data was genuinely invalid.
    if (err.code === '23514' || err.code === '23503') {
      return NextResponse.json({ error: 'Complaint rejected by validation rules' }, { status: 400 });
    }
    console.error('Failed to file complaint:', err);
    return NextResponse.json({ error: 'Could not file complaint' }, { status: 500 });
  }
}
