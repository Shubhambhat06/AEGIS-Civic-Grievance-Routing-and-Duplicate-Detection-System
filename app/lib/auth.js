// =====================================================================
// Authentication and role-based authorisation.
//
// Requirements 11 and 13:
//   - two kinds of user: CITIZEN and STAFF (staff are further split
//     into STAFF and ADMIN by the staff.role column);
//   - passwords are stored as bcrypt hashes, never in plain text;
//   - the session cookie is signed with an HMAC so it cannot be forged.
//
// A signed cookie is used instead of a JWT library to keep the
// dependency list small; the security property is the same - the client
// cannot change the cookie contents without knowing SESSION_SECRET.
// =====================================================================
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { cookies } from 'next/headers';
import { query } from './db';

const COOKIE_NAME = 'aegis_session';
const MAX_AGE_SECONDS = 60 * 60 * 8; // 8 hours

function secret() {
  const s = process.env.SESSION_SECRET;
  if (!s || s.length < 32) {
    throw new Error('SESSION_SECRET must be set and at least 32 characters long.');
  }
  return s;
}

function sign(payloadB64) {
  return crypto.createHmac('sha256', secret()).update(payloadB64).digest('base64url');
}

function encodeSession(session) {
  const payload = Buffer.from(JSON.stringify(session)).toString('base64url');
  return `${payload}.${sign(payload)}`;
}

function decodeSession(token) {
  if (!token || !token.includes('.')) return null;
  const [payload, signature] = token.split('.');

  // timingSafeEqual avoids leaking information through comparison speed
  const expected = sign(payload);
  if (
    signature.length !== expected.length ||
    !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))
  ) {
    return null;
  }

  const session = JSON.parse(Buffer.from(payload, 'base64url').toString());
  if (session.exp < Date.now() / 1000) return null;
  return session;
}

export async function hashPassword(plain) {
  return bcrypt.hash(plain, 10);
}

/**
 * Check an email and password against either the citizen or the staff
 * table and return a session object, or null if the login fails.
 *
 * The same generic failure is returned whether the email is unknown or
 * the password is wrong, so an attacker cannot use the response to
 * discover which accounts exist.
 */
export async function authenticate(email, password, userType) {
  const table = userType === 'staff' ? 'staff' : 'citizen';
  const idColumn = userType === 'staff' ? 'staff_id' : 'citizen_id';

  const rows = await query(
    `SELECT ${idColumn} AS id, email, full_name, password_hash
            ${userType === 'staff' ? ', role, dept_id' : ', ward_id'}
       FROM ${table}
      WHERE email = $1`,
    [email]
  );

  if (rows.length === 0) return null;

  const user = rows[0];
  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) return null;

  return {
    id: user.id,
    email: user.email,
    name: user.full_name,
    type: userType,                              // 'citizen' | 'staff'
    role: userType === 'staff' ? user.role : 'CITIZEN',
    deptId: user.dept_id ?? null,
    wardId: user.ward_id ?? null,
    exp: Math.floor(Date.now() / 1000) + MAX_AGE_SECONDS,
  };
}

export async function setSessionCookie(session) {
  (await cookies()).set(COOKIE_NAME, encodeSession(session), {
    httpOnly: true,                                    // not readable by JavaScript
    secure: process.env.NODE_ENV === 'production',     // HTTPS only in production
    sameSite: 'lax',                                   // basic CSRF protection
    path: '/',
    maxAge: MAX_AGE_SECONDS,
  });
}

export async function clearSessionCookie() {
  (await cookies()).delete(COOKIE_NAME);
}

export async function getSession() {
  const token = (await cookies()).get(COOKIE_NAME)?.value;
  return token ? decodeSession(token) : null;
}

/**
 * Guard for API routes.
 *
 *   requireRole()                  -> any logged-in user
 *   requireRole(['STAFF','ADMIN']) -> staff only
 *   requireRole(['ADMIN'])         -> admins only
 *
 * Returns { session } on success or { error, status } on failure.
 */
export async function requireRole(allowedRoles = null) {
  const session = await getSession();
  if (!session) return { error: 'Not signed in', status: 401 };
  if (allowedRoles && !allowedRoles.includes(session.role)) {
    return { error: 'Insufficient permissions', status: 403 };
  }
  return { session };
}
