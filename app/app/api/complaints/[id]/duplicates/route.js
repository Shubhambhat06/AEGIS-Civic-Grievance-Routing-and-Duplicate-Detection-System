// =====================================================================
// GET  /api/complaints/[id]/duplicates  -  similar earlier complaints
// POST /api/complaints/[id]/duplicates  -  merge this one into a parent
//
// This is the core feature of AEGIS. Both halves are thin wrappers over
// stored functions, so the similarity logic and the merge transaction
// live in the database rather than in the web layer.
// =====================================================================
import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { requireRole } from '@/lib/auth';

export async function GET(request, context) {
  const auth = await requireRole(['STAFF', 'ADMIN']);
  if (auth.error) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { id: rawId } = await context.params;
  const id = Number(rawId);
  if (!Number.isInteger(id)) {
    return NextResponse.json({ error: 'Invalid complaint id' }, { status: 400 });
  }

  const threshold = Number(request.nextUrl.searchParams.get('threshold') ?? 0.8);

  // fn_find_duplicates runs the vector similarity search.
  const candidates = await query(
    `SELECT * FROM fn_find_duplicates($1, $2, 5)`,
    [id, threshold]
  );

  return NextResponse.json({ candidates });
}


export async function POST(request, context) {
  const auth = await requireRole(['STAFF', 'ADMIN']);
  if (auth.error) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { session } = auth;
  const { id: rawId } = await context.params;
  const childId = Number(rawId);
  const { parentId, similarity } = await request.json();

  if (!Number.isInteger(childId) || !Number.isInteger(parentId)) {
    return NextResponse.json({ error: 'Invalid complaint ids' }, { status: 400 });
  }

  try {
    // fn_merge_duplicate does all three steps atomically: write the
    // link, mark the child MERGED, bump the parent counter. If any step
    // fails the whole thing is rolled back by PostgreSQL.
    await query(`SELECT fn_merge_duplicate($1, $2, $3, $4)`, [
      childId,
      parentId,
      similarity ?? 0,
      session.type === 'staff' ? session.id : null,
    ]);

    return NextResponse.json({ merged: true, childId, parentId });
  } catch (err) {
    // P0001 is a RAISE EXCEPTION from our own validation inside the
    // function, so the message is safe and useful to show the user.
    if (err.code === 'P0001') {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    if (err.code === '23505') {
      return NextResponse.json(
        { error: 'This complaint has already been merged' },
        { status: 409 }
      );
    }
    console.error('Merge failed:', err);
    return NextResponse.json({ error: 'Could not merge complaints' }, { status: 500 });
  }
}
