'use client';

// Landing page: what the service does, how a complaint moves through it,
// live figures, and sign-in.

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import RouteRail from '@/components/RouteRail';

const DEMO_ACCOUNTS = [
  { role: 'Citizen', userType: 'citizen', email: 'arjun.menon@example.com', what: 'Lodge and track grievances' },
  { role: 'Department officer', userType: 'staff', email: 'roads1@aegis.example', what: 'Roads department queue' },
  { role: 'Administrator', userType: 'staff', email: 'admin@aegis.example', what: 'City-wide overview' },
];
const DEMO_PASSWORD = 'password123';

export default function HomePage() {
  const router = useRouter();
  const [userType, setUserType] = useState('citizen');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [stats, setStats] = useState(null);

  useEffect(() => {
    fetch('/api/public/stats')
      .then((r) => (r.ok ? r.json() : null))
      .then(setStats)
      .catch(() => setStats(null));
  }, []);

  async function signIn(creds) {
    setBusy(true);
    setError('');
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(creds),
    });
    const data = await res.json();
    setBusy(false);

    if (!res.ok) {
      setError(
        creds.userType === 'staff'
          ? 'That email and password do not match a staff account. Citizens should choose "Citizen" above.'
          : 'That email and password do not match a citizen account. Officers should choose "Department officer" above.'
      );
      return;
    }
    if (data.user.role === 'ADMIN') router.push('/admin');
    else if (data.user.type === 'staff') router.push('/staff');
    else router.push('/citizen');
  }

  function handleSubmit(event) {
    event.preventDefault();
    signIn({ email, password, userType });
  }

  function signInAs(account) {
    setUserType(account.userType);
    setEmail(account.email);
    setPassword(DEMO_PASSWORD);
    signIn({ email: account.email, password: DEMO_PASSWORD, userType: account.userType });
  }

  return (
    <div className="hero">
      <section>
        <h1>Lodge a civic grievance. We send it to the right department.</h1>
        <p className="lede">
          Potholes, water supply, garbage, street lights, blocked drains. Describe
          the problem in your own words. You do not need to know which department
          handles it, and if your neighbours have already reported the same thing,
          your grievance is joined to theirs so it is fixed once.
        </p>

        <div className="panel journey">
          <h2 className="journey-title">How a grievance moves through the system</h2>
          <RouteRail explain />
        </div>

        <div className="facts">
          <h2 className="journey-title" style={{ marginLeft: 0 }}>Grievances so far</h2>
          <div className="figures">
            <div className="figure">
              <div className="value">{stats ? stats.received : '-'}</div>
              <div className="label">grievances lodged</div>
            </div>
            <div className="figure ok">
              <div className="value">{stats ? stats.resolved : '-'}</div>
              <div className="label">resolved</div>
            </div>
            <div className="figure">
              <div className="value">{stats ? stats.merged : '-'}</div>
              <div className="label">repeat reports joined to an earlier one</div>
            </div>
            <div className="figure">
              <div className="value">{stats?.avg_hours != null ? `${stats.avg_hours} h` : '-'}</div>
              <div className="label">average time to resolve</div>
            </div>
          </div>
          {stats && (
            <p className="small muted" style={{ marginTop: 10 }}>
              Covering {stats.wards} wards and {stats.departments} departments.
            </p>
          )}
        </div>
      </section>

      <aside className="panel">
        <div className="panel-head">
          <div>
            <h2>Sign in</h2>
            <p>To lodge a grievance or track one you have lodged.</p>
          </div>
        </div>
        <form className="panel-body" onSubmit={handleSubmit}>
          <fieldset className="field" style={{ border: 0, padding: 0, margin: 0 }}>
            <legend className="label-text">I am signing in as</legend>
            <div className="choice two">
              <input type="radio" id="role-citizen" name="userType" value="citizen"
                     checked={userType === 'citizen'} onChange={() => setUserType('citizen')} />
              <label htmlFor="role-citizen">Citizen</label>
              <input type="radio" id="role-staff" name="userType" value="staff"
                     checked={userType === 'staff'} onChange={() => setUserType('staff')} />
              <label htmlFor="role-staff">Department officer</label>
            </div>
          </fieldset>

          <div className="field">
            <label htmlFor="email">Email address</label>
            <input id="email" type="email" autoComplete="username" value={email}
                   onChange={(e) => setEmail(e.target.value)} required />
          </div>

          <div className="field">
            <label htmlFor="password">Password</label>
            <input id="password" type="password" autoComplete="current-password" value={password}
                   onChange={(e) => setPassword(e.target.value)} required />
          </div>

          <div className="field">
            <button type="submit" className="btn block" disabled={busy}>
              {busy ? 'Signing in' : 'Sign in'}
            </button>
            {error && <p className="error-text" role="alert">{error}</p>}
          </div>

          <div className="demo-accounts">
            <p>This is a demonstration with sample accounts. Choose one to sign in straight away.</p>
            <div className="demo-list">
              {DEMO_ACCOUNTS.map((a) => (
                <button key={a.email} type="button" onClick={() => signInAs(a)} disabled={busy}>
                  <span>
                    <span className="who-role">{a.role}</span>
                    <span className="who-mail" style={{ display: 'block' }}>{a.email}</span>
                  </span>
                  <span className="who-mail">{a.what}</span>
                </button>
              ))}
            </div>
          </div>
        </form>
      </aside>
    </div>
  );
}
