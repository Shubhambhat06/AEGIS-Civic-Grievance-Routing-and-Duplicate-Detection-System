// =====================================================================
// AEGIS - capture application screenshots for the project report.
//
// Drives a real Chromium browser through the whole demo flow and saves
// a PNG at each step into docs/screenshots/.
//
// Prerequisites:
//   - the database is seeded (bash scripts/run_tests.sh, or docker compose up)
//   - the app is running
//
// Usage:
//   npm install playwright          (once)
//   BASE=http://localhost:3000 node scripts/screenshots.mjs
// =====================================================================
import { chromium } from 'playwright';
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';

const BASE = process.env.BASE ?? 'http://localhost:3000';
const OUT = process.env.OUT ?? 'docs/screenshots';
const PSQL = process.env.PSQL_CMD ?? 'psql';
const PSQL_ARGS = (process.env.PSQL_ARGS ?? '-h /tmp -p 5433 -U postgres -d aegis_test').split(' ');

mkdirSync(OUT, { recursive: true });

function sql(statement) {
  return execFileSync(PSQL, [...PSQL_ARGS, '-X', '-tA', '-c', statement], {
    encoding: 'utf8',
  }).trim();
}

async function shot(page, name, label) {
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
  console.log(`  saved ${name}.png   ${label}`);
}

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });

try {
  // ---------------------------------------------------------------
  console.log('1. login page');
  const page = await ctx.newPage();
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await shot(page, '01-login', 'sign-in form with the role selector');

  // ---------------------------------------------------------------
  console.log('2. citizen files a new complaint');
  await page.selectOption('#userType', 'citizen');
  await page.fill('#email', 'arjun.menon@example.com');
  await page.fill('#password', 'password123');
  await page.click('button[type="submit"]');
  await page.waitForURL('**/citizen');
  await page.waitForSelector('table');

  await page.fill('#title', 'Yet another pothole by the bus stop');
  await page.fill(
    '#description',
    'The same deep pothole next to the bus stop on the main road is still there and getting worse after the rain.'
  );
  await page.selectOption('#priority', 'HIGH');
  await shot(page, '02-citizen-file', 'complaint being filed, tracker beside it');

  await page.click('button[type="submit"]');
  await page.waitForSelector('.success');
  const confirmation = await page.textContent('.success');
  console.log(`   ${confirmation.trim()}`);
  await shot(page, '03-citizen-submitted', 'complaint accepted, appears in the tracker');

  // ---------------------------------------------------------------
  // The embedding pipeline is asynchronous. In production this is
  // scripts/embed.py; for the demo it is the SQL equivalent. Running
  // it also fires the auto-routing trigger.
  console.log('3. running the embedding pipeline');
  const newId = Number(confirmation.match(/#(\d+)/)[1]);
  sql(`INSERT INTO complaint_embedding (complaint_id, embedding, model_name)
       SELECT c.complaint_id, fn_demo_embedding(c.title || ' ' || c.description), 'demo-hashing-384'
       FROM complaint c
       WHERE NOT EXISTS (SELECT 1 FROM complaint_embedding e WHERE e.complaint_id = c.complaint_id)`);
  const routed = sql(
    `SELECT COALESCE(d.dept_name,'(unrouted)') FROM complaint c
      LEFT JOIN department d ON d.dept_id=c.dept_id WHERE c.complaint_id=${newId}`
  );
  console.log(`   complaint #${newId} auto-routed to: ${routed}`);

  // ---------------------------------------------------------------
  console.log('4. citizen whose complaint was merged as a duplicate');
  const p2 = await ctx.newPage();
  await p2.goto(BASE, { waitUntil: 'networkidle' });
  await p2.selectOption('#userType', 'citizen');
  await p2.fill('#email', 'divya.rao@example.com');
  await p2.fill('#password', 'password123');
  await p2.click('button[type="submit"]');
  await p2.waitForURL('**/citizen');
  await p2.waitForSelector('table');
  await shot(p2, '04-citizen-merged', 'merged complaint still tracks its parent issue');
  await p2.close();

  // ---------------------------------------------------------------
  console.log('5. staff queue and duplicate detection');
  const p3 = await ctx.newPage();
  await p3.goto(BASE, { waitUntil: 'networkidle' });
  await p3.selectOption('#userType', 'staff');
  await p3.fill('#email', 'roads1@bbmp.gov.in');
  await p3.fill('#password', 'password123');
  await p3.click('button[type="submit"]');
  await p3.waitForURL('**/staff');
  await p3.waitForSelector('table tbody tr');
  await shot(p3, '05-staff-queue', 'Roads department queue, sorted by SLA urgency');

  // click "Check duplicates" on the row for the complaint just filed
  const row = p3.locator('tbody tr', { hasText: 'Yet another pothole' }).first();
  if (await row.count()) {
    await row.getByRole('button', { name: 'Check duplicates' }).click();
    await p3.waitForSelector('.card');
    await shot(p3, '06-staff-duplicates', 'similarity search flags the existing pothole report');

    const candidates = await p3.locator('.card tbody tr').count();
    console.log(`   ${candidates} duplicate candidate(s) shown`);

    if (candidates > 0) {
      const before = sql(`SELECT duplicate_count FROM complaint WHERE complaint_id=15`);
      await p3.locator('.card tbody tr').first()
        .getByRole('button', { name: 'Merge into this' }).click();
      await p3.waitForSelector('.success');
      const after = sql(`SELECT duplicate_count FROM complaint WHERE complaint_id=15`);
      console.log(`   merged; #15 duplicate_count ${before} -> ${after}`);
      await shot(p3, '07-staff-merged', 'merge confirmed, duplicate removed from the queue');
    }
  } else {
    console.log('   WARNING: the new complaint is not in this queue');
  }
  await p3.close();

  // ---------------------------------------------------------------
  console.log('6. admin dashboard');
  const p4 = await ctx.newPage();
  await p4.goto(BASE, { waitUntil: 'networkidle' });
  await p4.selectOption('#userType', 'staff');
  await p4.fill('#email', 'admin@bbmp.gov.in');
  await p4.fill('#password', 'password123');
  await p4.click('button[type="submit"]');
  await p4.waitForURL('**/admin');
  await p4.waitForSelector('table');
  await shot(p4, '08-admin-dashboard', 'department performance and most-duplicated issues');

  // An ADMIN is not restricted to one department, so the same staff
  // queue shows every ward and the overdue complaints in red.
  await p4.goto(BASE + '/staff', { waitUntil: 'networkidle' });
  await p4.waitForSelector('tbody tr');
  const breached = await p4.locator('td.breached').count();
  console.log(`   ${breached} complaint(s) past their SLA deadline`);
  await shot(p4, '09-admin-all-queue', 'cross-department queue, breached SLAs in red');
  await p4.close();

  console.log('\nAll screenshots written to ' + OUT);
} finally {
  await browser.close();
}
