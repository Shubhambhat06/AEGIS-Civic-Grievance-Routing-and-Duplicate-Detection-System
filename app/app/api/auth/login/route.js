// POST /api/auth/login  -  sign in as a citizen or a staff member
import { NextResponse } from 'next/server';
import { authenticate, setSessionCookie } from '@/lib/auth';

export async function POST(request) {
  const { email, password, userType } = await request.json();

  if (!email || !password) {
    return NextResponse.json({ error: 'Email and password are required' }, { status: 400 });
  }

  const session = await authenticate(email, password, userType === 'staff' ? 'staff' : 'citizen');

  // Deliberately vague: do not reveal whether the account exists.
  if (!session) {
    return NextResponse.json({ error: 'Invalid email or password' }, { status: 401 });
  }

  await setSessionCookie(session);
  return NextResponse.json({
    user: { name: session.name, role: session.role, type: session.type },
  });
}
