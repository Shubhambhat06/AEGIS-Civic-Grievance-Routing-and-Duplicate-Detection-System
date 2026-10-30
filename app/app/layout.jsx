import './globals.css';

export const metadata = {
  title: 'AEGIS - Civic Grievance Portal',
  description: 'File, track and resolve municipal complaints',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>
        <header className="site-header">
          <strong>AEGIS</strong>
          <span className="tagline">Civic Grievance Routing</span>
        </header>
        <main className="container">{children}</main>
      </body>
    </html>
  );
}
