// =====================================================================
// GET   /api/complaints/[id]  -  one complaint with its audit trail
// PATCH /api/complaints/[id]  -  staff update status / assignee
// =====================================================================
import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { requireRole } from '@/lib/auth';

export async function GET(request, context) {
  const auth = await requireRole();
  if (auth.error) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { session } = auth;
  const { id: rawId } = await context.params;
  const id = Number(rawId);
  if (!Number.isInteger(id)) {
    return NextResponse.json({ error: 'Invalid complaint id' }, { status: 400 });
  }

  const [complaint] = await query(
    `SELECT c.complaint_id, c.title, c.description, c.status, c.priority,
            c.filed_at, c.sla_deadline, c.resolved_at, c.duplicate_count,
            c.latitude, c.longitude,
            d.dept_name, w.ward_name,
            ct.full_name AS filed_by,
            s.full_name  AS assigned_to
       FROM complaint c
       JOIN ward      w  ON w.ward_id     = c.ward_id
       JOIN citizen   ct ON ct.citizen_id = c.citizen_id
       LEFT JOIN department d ON d.dept_id  = c.dept_id
       LEFT JOIN staff      s ON s.staff_id = c.assigned_staff_id
      WHERE c.complaint_id = $1
        AND ($2::INT IS NULL OR c.citizen_id = $2)`,
    [id, session.type === 'citizen' ? session.id : null]
  );

  if (!complaint) {
    return NextResponse.json({ error: 'Complaint not found' }, { status: 404 });
  }

  const history = await query(
    `SELECT sh.changed_at, sh.old_status, sh.new_status, sh.remarks,
            COALESCE(s.full_name, 'system') AS changed_by
       FROM status_history sh
       LEFT JOIN staff s ON s.staff_id = sh.changed_by
      WHERE sh.complaint_id = $1
      ORDER BY sh.changed_at`,
    [id]
  );

  const attachments = await query(
    `SELECT attachment_url FROM complaint_attachment WHERE complaint_id = $1`,
    [id]
  );

  return NextResponse.json({ complaint, history, attachments });
}


export async function PATCH(request, context) {
  const auth = await requireRole(['STAFF', 'ADMIN']);
  if (auth.error) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { session } = auth;
  const { id: rawId } = await context.params;
  const id = Number(rawId);
  const { status, assignedStaffId } = await request.json();

  const ALLOWED = ['ROUTED', 'IN_PROGRESS', 'RESOLVED', 'ESCALATED'];
  if (status && !ALLOWED.includes(status)) {
    return NextResponse.json({ error: 'Invalid status value' }, { status: 400 });
  }

  // "Start work" from the staff screen sends IN_PROGRESS with no assignee:
  // the person clicking it is taking the complaint on.
  const assignee =
    assignedStaffId ?? (status === 'IN_PROGRESS' && session.type === 'staff' ? session.id : null);

  try {
    // COALESCE leaves a column unchanged when the caller omits it.
    // A plain STAFF member can only touch complaints in their own
    // department; an ADMIN can touch any.
    const rows = await query(
      `UPDATE complaint
          SET status            = COALESCE($2::complaint_status, status),
              assigned_staff_id = COALESCE($3::INT, assigned_staff_id)
        WHERE complaint_id = $1
          AND ($4::INT IS NULL OR dept_id = $4)
      RETURNING complaint_id, status, assigned_staff_id`,
      [id, status ?? null, assignee,
       session.role === 'ADMIN' ? null : session.deptId]
    );

    if (rows.length === 0) {
      return NextResponse.json(
        { error: 'Complaint not found, or not in your department' },
        { status: 404 }
      );
    }

    return NextResponse.json({ complaint: rows[0] });
  } catch (err) {
    // The validation trigger raises for illegal transitions, for
    // example trying to reopen a resolved complaint.
    if (err.code === 'P0001') {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    console.error('Failed to update complaint:', err);
    return NextResponse.json({ error: 'Could not update complaint' }, { status: 500 });
  }
}
