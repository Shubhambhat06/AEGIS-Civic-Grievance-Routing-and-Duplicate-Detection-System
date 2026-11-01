import '@fontsource-variable/noto-sans';
import '@fontsource-variable/noto-sans-devanagari';
import './globals.css';
import SiteHeader from '@/components/SiteHeader';
import Footer from '@/components/Footer';

export const metadata = {
  title: 'AEGIS - Municipal Grievance Redressal Portal (demonstration)',
  description: 'Lodge civic grievances, track them, and see how the city responds. A student demonstration project.',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>
        <SiteHeader />
        <main id="main-content" tabIndex={-1} className="wrap">{children}</main>
        <Footer />
      </body>
    </html>
  );
}
