// GET /api/auth/me  -  who is signed in (used by the page header)
import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth';

export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ user: null });
  return NextResponse.json({
    user: { name: session.name, role: session.role, type: session.type },
  });
}
