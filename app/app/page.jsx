'use client';

// Landing page with the sign-in form.
// The same form serves both roles; the "I am a" selector decides which
// table the credentials are checked against.

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export default function LoginPage() {
  const router = useRouter();
  const [userType, setUserType] = useState('citizen');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError('');

    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, userType }),
    });

    const data = await res.json();
    setBusy(false);

    if (!res.ok) {
      setError(data.error ?? 'Sign in failed');
      return;
    }

    if (data.user.role === 'ADMIN') router.push('/admin');
    else if (data.user.type === 'staff') router.push('/staff');
    else router.push('/citizen');
  }

  return (
    <div style={{ maxWidth: 420 }}>
      <h1>Sign in</h1>
      <p className="sub">
        Report a civic issue, or sign in as municipal staff to manage the queue.
      </p>

      <form onSubmit={handleSubmit}>
        <label htmlFor="userType">I am a</label>
        <select
          id="userType"
          value={userType}
          onChange={(e) => setUserType(e.target.value)}
        >
          <option value="citizen">Citizen</option>
          <option value="staff">Municipal staff</option>
        </select>

        <label htmlFor="email">Email</label>
        <input
          id="email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />

        <label htmlFor="password">Password</label>
        <input
          id="password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />

        <button type="submit" disabled={busy}>
          {busy ? 'Signing in...' : 'Sign in'}
        </button>

        {error && <p className="error">{error}</p>}
      </form>
    </div>
  );
}
