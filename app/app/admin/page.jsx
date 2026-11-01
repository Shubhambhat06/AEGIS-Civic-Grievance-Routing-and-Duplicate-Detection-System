'use client';

// Administrator overview: how every department is doing, where the
// complaints come from, and which problems keep being reported.

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { HBars, Legend, SlaBars, StackBar, Columns } from '@/components/charts';
import { STATUS_LABEL, regNo } from '@/components/format';

const STATUS_PARTS = [
  { key: 'RESOLVED', cls: 'seg-resolved' },
  { key: 'IN_PROGRESS', cls: 'seg-progress' },
  { key: 'ROUTED', cls: 'seg-open' },
  { key: 'OPEN', cls: 'seg-idle' },
  { key: 'ESCALATED', cls: 'seg-escalated' },
  { key: 'MERGED', cls: 'seg-merged' },
];

export default function AdminPage() {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  const [sweep, setSweep] = useState(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    const res = await fetch('/api/dashboard');
    const body = await res.json();
    if (!res.ok) { setError(body.error); return; }
    setData(body);
  }

  useEffect(() => { load(); }, []);

  async function runSweep() {
    setBusy(true);
    const res = await fetch('/api/admin/escalate', { method: 'POST' });
    const body = await res.json();
    setBusy(false);
    setSweep(res.ok ? body.escalated : null);
    load();
  }

  if (error) {
    return (
      <div className="notice bad">
        <h3>This page is for administrators</h3>
        <p>{error === 'Not signed in' ? 'Sign in with an administrator account to see it.' : 'Your account cannot view the city-wide overview.'}</p>
        <p><Link href="/">Go to sign in</Link></p>
      </div>
    );
  }
  if (!data) return <p className="empty">Loading the overview</p>;

  const t = data.totals;
  const deptRows = data.departments.map((d) => {
    const escalated = Number(d.escalated_count);
    const open = Number(d.open_count) - escalated;
    const resolved = Number(d.resolved_count);
    const total = Number(d.total_complaints);
    return {
      label: d.dept_name,
      total,
      segments: [
        { value: resolved, cls: 'seg-resolved', title: 'Resolved' },
        { value: open, cls: 'seg-open', title: 'Open' },
        { value: escalated, cls: 'seg-escalated', title: 'Overdue' },
        { value: total - resolved - open - escalated, cls: 'seg-merged', title: 'Joined to another report' },
      ],
    };
  });

  const statusCount = Object.fromEntries(data.statuses.map((s) => [s.status, s.n]));
  const statusParts = STATUS_PARTS.map((p) => ({
    label: STATUS_LABEL[p.key], cls: p.cls, value: statusCount[p.key] ?? 0,
  }));

  const wardRows = data.wards.map((w) => ({
    label: `${w.ward_name} (${w.zone})`,
    total: w.complaint_count,
    segments: [{ value: w.complaint_count, cls: 'seg-plain', title: 'Grievances' }],
  }));

  return (
    <>
      <div className="page-head">
        <div>
          <h1>City overview</h1>
          <p className="lede">
            How each department is performing. The figures update as grievances are
            lodged, joined to earlier reports and resolved.
          </p>
        </div>
        <div style={{ textAlign: 'right' }}>
          <button type="button" className="btn secondary" onClick={runSweep} disabled={busy}>
            {busy ? 'Checking' : 'Check for overdue grievances'}
          </button>
          <p className="small muted" style={{ marginTop: 6 }}>In a live deployment this runs on a schedule.</p>
        </div>
      </div>

      {sweep !== null && (
        <div className={`notice ${sweep > 0 ? 'warn' : 'ok'}`} role="status" style={{ marginBottom: 24 }}>
          <p>
            {sweep > 0
              ? `${sweep} ${sweep === 1 ? 'grievance was' : 'grievances were'} past the deadline and ${sweep === 1 ? 'has' : 'have'} been escalated.`
              : 'No open grievance is past its deadline. Nothing was escalated.'}
          </p>
        </div>
      )}

      <div className="figures" style={{ marginBottom: 24 }}>
        <div className="figure"><div className="value">{t.received}</div><div className="label">grievances lodged</div></div>
        <div className="figure"><div className="value">{t.open}</div><div className="label">still open</div></div>
        <div className="figure ok"><div className="value">{t.resolved}</div><div className="label">resolved</div></div>
        <div className={`figure${t.overdue ? ' bad' : ''}`}><div className="value">{t.overdue}</div><div className="label">past their deadline</div></div>
        <div className="figure"><div className="value">{t.merged}</div><div className="label">repeat reports joined</div></div>
      </div>

      <div className="stack">
        <div className="grid-2">
          <section className="panel">
            <div className="panel-head">
              <div>
                <h2>Grievances by department</h2>
                <p>Every grievance each department has received, by where it stands now.</p>
              </div>
            </div>
            <div className="panel-body">
              <HBars rows={deptRows} />
              <Legend items={[
                { label: 'Resolved', cls: 'seg-resolved' },
                { label: 'Open', cls: 'seg-open' },
                { label: 'Overdue', cls: 'seg-escalated' },
                { label: 'Joined to another report', cls: 'seg-merged' },
              ]} />
            </div>
          </section>

          <section className="panel">
            <div className="panel-head">
              <div>
                <h2>Time to resolve against target</h2>
                <p>Average hours taken. The black line is the department's own deadline.</p>
              </div>
            </div>
            <div className="panel-body">
              <SlaBars rows={data.sla} />
              <Legend items={[
                { label: 'Within target', cls: 'seg-resolved' },
                { label: 'Slower than target', cls: 'seg-escalated' },
              ]} />
            </div>
          </section>
        </div>

        <section className="panel">
          <div className="panel-head">
            <div>
              <h2>Grievances lodged each week</h2>
              <p>The last 13 weeks, by the week the grievance was lodged.</p>
            </div>
          </div>
          <div className="panel-body">
            <Columns data={data.weekly} />
          </div>
        </section>

        <div className="grid-2">
          <section className="panel">
            <div className="panel-head">
              <div>
                <h2>Where every grievance stands</h2>
                <p>All {t.received} grievances by current status.</p>
              </div>
            </div>
            <div className="panel-body">
              <StackBar parts={statusParts} />
            </div>
          </section>

          <section className="panel">
            <div className="panel-head">
              <div>
                <h2>Grievances by ward</h2>
                <p>Including repeat reports.</p>
              </div>
            </div>
            <div className="panel-body">
              <HBars rows={wardRows} />
            </div>
          </section>
        </div>

        <section className="panel">
          <div className="panel-head">
            <div>
              <h2>Problems reported more than once</h2>
              <p>
                Each of these was reported by several people. The repeat reports were
                joined to the first one, so each problem sits in one queue, once.
              </p>
            </div>
          </div>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Grievance</th>
                  <th>Ward</th>
                  <th>Status</th>
                  <th className="right">Times reported</th>
                </tr>
              </thead>
              <tbody>
                {data.duplicates.map((d) => (
                  <tr key={d.complaint_id}>
                    <td><div className="cell-title">{d.title}</div><div className="cell-sub">{regNo(d.complaint_id)}</div></td>
                    <td>{d.ward_name}</td>
                    <td><span className={`tag ${d.status}`}>{STATUS_LABEL[d.status]}</span></td>
                    <td className="right"><strong>{1 + d.merged_count}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
            {data.duplicates.length === 0 && <p className="empty">No repeat reports have been joined yet.</p>}
          </div>
        </section>
      </div>
    </>
  );
}
