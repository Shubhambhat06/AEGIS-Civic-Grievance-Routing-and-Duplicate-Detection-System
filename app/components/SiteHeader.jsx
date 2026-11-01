'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import Seal from './Seal';

const NAV = {
  CITIZEN: [{ href: '/citizen', label: 'My grievances' }],
  STAFF: [{ href: '/staff', label: 'Work queue' }],
  ADMIN: [
    { href: '/admin', label: 'Overview' },
    { href: '/staff', label: 'All grievances' },
  ],
};

const ROLE_LABEL = { CITIZEN: 'Citizen', STAFF: 'Department officer', ADMIN: 'Administrator' };

const SIZES = [
  { key: 'sm', label: 'A-', name: 'Smaller text' },
  { key: 'md', label: 'A', name: 'Normal text' },
  { key: 'lg', label: 'A+', name: 'Larger text' },
];

export default function SiteHeader() {
  const pathname = usePathname();
  const router = useRouter();
  const [user, setUser] = useState(undefined);
  const [size, setSize] = useState('md');

  // Re-check who is signed in whenever the page changes, so the header
  // updates straight after signing in or out.
  useEffect(() => {
    let active = true;
    fetch('/api/auth/me')
      .then((res) => (res.ok ? res.json() : { user: null }))
      .then((data) => active && setUser(data.user))
      .catch(() => active && setUser(null));
    return () => { active = false; };
  }, [pathname]);

  // Remember the reader's text size. Storage can be unavailable (private
  // windows, blocked site data), so every access is guarded.
  useEffect(() => {
    let saved = 'md';
    try { saved = localStorage.getItem('aegis-text') || 'md'; } catch {}
    applySize(saved);
  }, []);

  function applySize(key) {
    setSize(key);
    document.documentElement.dataset.text = key;
    try { localStorage.setItem('aegis-text', key); } catch {}
  }

  async function signOut() {
    await fetch('/api/auth/logout', { method: 'POST' });
    setUser(null);
    router.push('/');
  }

  const links = user ? NAV[user.role] ?? [] : [];

  return (
    <header>
      <a className="skip-link" href="#main-content">Skip to main content</a>
      <div className="tricolour" aria-hidden="true" />
      <div className="utility">
        <div className="wrap">
          <span className="disclaimer">
            <strong>Demonstration portal.</strong> Not an official government website.
          </span>
          <div className="text-size" role="group" aria-label="Text size">
            <span>Text size</span>
            {SIZES.map((s) => (
              <button key={s.key} type="button" aria-label={s.name} aria-pressed={size === s.key}
                      onClick={() => applySize(s.key)}>
                {s.label}
              </button>
            ))}
          </div>
        </div>
      </div>
      <div className="masthead">
        <div className="wrap">
          <Link href="/" className="brand">
            <Seal />
            <span>
              <span className="brand-name">AEGIS</span>
              <span className="brand-hi" lang="hi">नागरिक शिकायत निवारण पोर्टल</span>
              <span className="brand-sub">Municipal Grievance Redressal Portal</span>
            </span>
          </Link>

          {links.length > 0 && (
            <nav className="nav" aria-label="Main">
              {links.map((l) => (
                <Link key={l.href} href={l.href} aria-current={pathname === l.href ? 'page' : undefined}>
                  {l.label}
                </Link>
              ))}
            </nav>
          )}

          {user && (
            <div className="who">
              <span>
                <strong>{user.name}</strong>
                {ROLE_LABEL[user.role]}
              </span>
              <button type="button" className="btn secondary small" onClick={signOut}>
                Sign out
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
