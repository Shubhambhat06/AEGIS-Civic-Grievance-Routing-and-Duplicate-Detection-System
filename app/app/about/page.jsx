// About, help, accessibility, privacy and terms - the pages a public
// portal's footer links to. Kept on one page with anchors.

export const metadata = { title: 'About this portal - AEGIS' };

export default function AboutPage() {
  return (
    <div className="prose">
      <h1>About this portal</h1>
      <p className="lede" style={{ marginTop: 8 }}>
        AEGIS is a demonstration of a municipal grievance redressal portal, built as a
        database project at PES University. It is not run by, or connected to, any government body.
      </p>
      <nav className="toc" aria-label="On this page">
        <a href="#how">How grievances are handled</a>
        <a href="#help">Help</a>
        <a href="#accessibility">Accessibility</a>
        <a href="#privacy">Privacy</a>
        <a href="#terms">Terms of use</a>
      </nav>

      <h2 id="how">How grievances are handled</h2>
      <ul>
        <li><strong>Lodged.</strong> You describe the problem in your own words. You receive a registration number such as AEG/00025.</li>
        <li><strong>Checked for repeats.</strong> Your description is compared by meaning with earlier grievances from your ward, so a problem reported by several people is handled once.</li>
        <li><strong>Sent to a department.</strong> It goes to the department that resolved the most similar problems before. You do not have to choose one.</li>
        <li><strong>Resolved.</strong> Each department has a fixed number of hours to resolve a grievance. Grievances that pass this deadline are escalated automatically.</li>
      </ul>

      <h2 id="help">Help</h2>
      <p><strong>How do I lodge a grievance?</strong> Sign in as a citizen and fill in the form under "Lodge a grievance".</p>
      <p><strong>How do I track it?</strong> Every grievance you have lodged is listed on "My grievances". Select one to see where it is on its route and its full history.</p>
      <p><strong>My grievance says "Joined to an earlier report". What does that mean?</strong> Someone in your ward had already reported the same problem. Yours was joined to theirs so that the department fixes it once. You can still follow its progress from your list.</p>
      <p><strong>Sample accounts.</strong> This demonstration has sample citizen, department officer and administrator accounts. They are listed on the sign-in page and all use the password <code>password123</code>.</p>

      <h2 id="accessibility">Accessibility statement</h2>
      <p>This portal aims to be usable by everyone, following the spirit of the Guidelines for Indian Government Websites and WCAG 2.1. It provides:</p>
      <ul>
        <li>a "Skip to main content" link as the first item on every page;</li>
        <li>text size controls (A-, A, A+) in the top bar, remembered on your device;</li>
        <li>full keyboard operation, with a visible focus outline;</li>
        <li>text and status colours chosen for strong contrast, with status always also written in words;</li>
        <li>labelled form fields and charts described in text for screen readers;</li>
        <li>a layout that works on phones without sideways scrolling.</li>
      </ul>

      <h2 id="privacy">Privacy policy</h2>
      <p>All people, grievances and contact details in this demonstration are invented sample data.</p>
      <ul>
        <li>Passwords are stored only as bcrypt hashes, never in readable form.</li>
        <li>Your session is kept in a signed, http-only cookie that page scripts cannot read and that cannot be altered without detection.</li>
        <li>Citizens can see only their own grievances. Department officers see their own department's queue.</li>
        <li>The figures on the home page are totals only. They contain no names and no grievance text.</li>
      </ul>

      <h2 id="terms">Terms of use</h2>
      <p>
        This is a student project for teaching and assessment. It does not provide any real
        municipal service, and grievances lodged here are not sent to any authority. For a
        real civic problem, contact your local municipal body through its official channels.
      </p>
    </div>
  );
}
