import Link from 'next/link';

const LINKS = [
  { href: '/about', label: 'About this portal' },
  { href: '/about#help', label: 'Help' },
  { href: '/about#accessibility', label: 'Accessibility statement' },
  { href: '/about#privacy', label: 'Privacy policy' },
  { href: '/about#terms', label: 'Terms of use' },
];

export default function Footer() {
  return (
    <footer className="footer">
      <div className="wrap">
        <div className="footer-links">
          {LINKS.map((l) => <Link key={l.href} href={l.href}>{l.label}</Link>)}
        </div>
        <div className="footer-meta">
          <span>AEGIS is a student project for DBMS, PES University. It is not an official government website.</span>
          <span>All names, grievances and contact details shown are sample data.</span>
        </div>
      </div>
    </footer>
  );
}
