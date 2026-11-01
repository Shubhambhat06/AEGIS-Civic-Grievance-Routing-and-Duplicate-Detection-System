// =====================================================================
// AEGIS - capture application screenshots for the project report.
//
// Drives a real Chromium browser through the whole demo flow and saves
// a PNG at each step into docs/screenshots/. Run it against a freshly
// seeded database so the numbers match the write-up.
//
// Usage:
//   npm install playwright && npx playwright install chromium
//   BASE=http://localhost:3000 node scripts/screenshots.mjs
// =====================================================================
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = process.env.BASE ?? 'http://localhost:3000';
const OUT = process.env.OUT ?? 'docs/screenshots';
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1366, height: 900 } });
const page = await ctx.newPage();

async function shot(name, label) {
  await page.waitForTimeout(300);
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
  console.log(`  saved ${name}.png   ${label}`);
}

async function signInAs(role) {
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.locator('.demo-list button', { hasText: role }).click();
}

async function signOut() {
  await page.getByRole('button', { name: 'Sign out' }).click();
  await page.waitForURL(BASE + '/');
}

try {
  console.log('1. landing page');
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.waitForSelector('.figure .value');
  await shot('01-login', 'how the service works, live figures, sign-in');

  console.log('2. citizen lodges a grievance');
  await signInAs('Citizen');
  await page.waitForURL('**/citizen');
  await page.waitForSelector('.complaint-item');
  await page.fill('#title', 'Pothole by the bus stop is getting worse');
  await page.fill(
    '#description',
    'The deep pothole on the main road next to the bus stop is bigger after the rain and bikes keep swerving into traffic.'
  );
  await page.click('label[for="prio-HIGH"]');
  await shot('02-citizen-file', 'report form filled in');

  await page.click('button[type="submit"]');
  await page.waitForSelector('.notice.ok');
  const reg = (await page.textContent('.notice.ok p strong')).trim();
  console.log(`   grievance registered as ${reg}`);
  await shot('03-citizen-submitted', 'routed straight away, similar reports flagged');
  await signOut();

  console.log('3. citizen whose report was joined to an earlier one');
  await page.getByRole('radio', { name: 'Citizen' }).check({ force: true });
  await page.fill('#email', 'divya.rao@example.com');
  await page.fill('#password', 'password123');
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await page.waitForURL('**/citizen');
  await page.waitForSelector('.complaint-item');
  await page.locator('.complaint-item summary').first().click();
  await shot('04-citizen-merged', 'joined report still tracks the earlier complaint');
  await signOut();

  console.log('4. staff queue and repeat-report check');
  await signInAs('Department officer');
  await page.waitForURL('**/staff');
  await page.waitForSelector('tbody tr');
  await shot('05-staff-queue', 'department queue, most urgent first');

  await page.locator('tbody tr', { hasText: 'Pothole by the bus stop' }).first().click();
  await page.waitForSelector('.match');
  await shot('06-staff-duplicates', 'earlier reports ranked by similarity of meaning');

  await page.locator('.match').first().getByRole('button', { name: 'Join to this one' }).click();
  await page.getByRole('button', { name: 'Confirm join' }).click();
  await page.waitForSelector('.notice.ok');
  console.log(`   ${reg} joined to the earlier report`);
  await shot('07-staff-merged', 'joined, removed from the queue');
  await signOut();

  console.log('5. administrator');
  await signInAs('Administrator');
  await page.waitForURL('**/admin');
  await page.waitForSelector('.hbars');
  await shot('08-admin-dashboard', 'department performance and repeat reports');

  await page.getByRole('button', { name: 'Check for overdue grievances' }).click();
  await page.waitForSelector('.notice[role="status"]');
  await page.goto(BASE + '/staff', { waitUntil: 'networkidle' });
  await page.waitForSelector('tbody tr');
  await shot('09-admin-all-queue', 'every department, overdue complaints escalated');

  console.log('\nAll screenshots written to ' + OUT);
} finally {
  await browser.close();
}
