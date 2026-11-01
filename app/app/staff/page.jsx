'use client';

// Officer work queue. Most urgent first; select a grievance to see it in
// full, check it against earlier reports from the same ward, join it to
// one of them, or move it along.

import { useEffect, useMemo, useState } from 'react';
import RouteRail from '@/components/RouteRail';
import Deadline from '@/components/Deadline';
import { STATUS_LABEL, PRIORITY_LABEL, formatDateTime, regNo } from '@/components/format';

const FILTERS = [
  { key: 'all', label: 'All open', test: () => true },
  { key: 'overdue', label: 'Overdue', test: (c) => c.is_breached },
  { key: 'soon', label: 'Due within 12 h', test: (c) => !c.is_breached && Number(c.hours_remaining) < 12 },
  { key: 'new', label: 'Not started', test: (c) => c.status === 'ROUTED' || c.status === 'OPEN' },
  { key: 'progress', label: 'In progress', test: (c) => c.status === 'IN_PROGRESS' },
];

function verdict(sim) {
  if (sim >= 0.7) return { text: 'Very likely the same', strong: true };
  if (sim >= 0.55) return { text: 'Possibly the same', strong: true };
  return { text: 'Weak match', strong: false };
}

export default function StaffPage() {
  const [me, setMe] = useState(null);
  const [complaints, setComplaints] = useState(null);
  const [filter, setFilter] = useState('all');
  const [search, setSearch] = useState('');
  const [selectedId, setSelectedId] = useState(null);
  const [message, setMessage] = useState(null);

  async function loadQueue() {
    const res = await fetch('/api/complaints');
    setComplaints(res.ok ? (await res.json()).complaints : []);
  }

  useEffect(() => {
    fetch('/api/auth/me').then((r) => (r.ok ? r.json() : { user: null })).then((d) => setMe(d.user));
    loadQueue();
  }, []);

  const isAdmin = me?.role === 'ADMIN';

  const visible = useMemo(() => {
    if (!complaints) return [];
    const f = FILTERS.find((x) => x.key === filter);
    const q = search.trim().toLowerCase();
    return complaints.filter(f.test).filter((c) =>
      !q ||
      c.title.toLowerCase().includes(q) ||
      c.ward_name.toLowerCase().includes(q) ||
      regNo(c.complaint_id).toLowerCase().includes(q) ||
      (q.replace(/\D/g, '') !== '' && String(c.complaint_id) === q.replace(/\D/g, '').replace(/^0+/, ''))
    );
  }, [complaints, filter, search]);

  const totals = useMemo(() => {
    const list = complaints ?? [];
    return {
      open: list.length,
      overdue: list.filter((c) => c.is_breached).length,
      soon: list.filter((c) => !c.is_breached && Number(c.hours_remaining) < 12).length,
      joined: list.reduce((a, c) => a + Number(c.duplicate_count || 0), 0),
    };
  }, [complaints]);

  function onChanged(text) {
    setMessage(text);
    loadQueue();
  }

  return (
    <>
      <div className="page-head">
        <div>
          <h1>{isAdmin ? 'All open grievances' : 'Work queue'}</h1>
          <p className="lede">
            {isAdmin ? 'Every department' : 'Grievances sent to your department'}, most urgent
            first. Select one to see the details, check whether it repeats an earlier
            report, and update its status.
          </p>
        </div>
      </div>

      <div className="figures" style={{ marginBottom: 24 }}>
        <div className="figure"><div className="value">{totals.open}</div><div className="label">open grievances</div></div>
        <div className={`figure${totals.overdue ? ' bad' : ''}`}><div className="value">{totals.overdue}</div><div className="label">past their deadline</div></div>
        <div className="figure"><div className="value">{totals.soon}</div><div className="label">due within 12 hours</div></div>
        <div className="figure"><div className="value">{totals.joined}</div><div className="label">repeat reports joined</div></div>
      </div>

      {message && (
        <div className="notice ok" role="status" style={{ marginBottom: 24 }}>
          <p>{message}</p>
        </div>
      )}

      <div className="grid-side">
        <section className="panel">
          <div className="toolbar">
            <div className="filters" role="group" aria-label="Filter grievances">
              {FILTERS.map((f) => {
                const n = (complaints ?? []).filter(f.test).length;
                return (
                  <button key={f.key} type="button" className="chip"
                          aria-pressed={filter === f.key} onClick={() => setFilter(f.key)}>
                    {f.label}<span className="count">{n}</span>
                  </button>
                );
              })}
            </div>
            <input type="search" placeholder="Search title, ward or AEG no." aria-label="Search grievances"
                   value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>

          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Grievance</th>
                  {isAdmin && <th>Department</th>}
                  <th>Status</th>
                  <th>Deadline</th>
                  <th className="right">Reports</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((c) => (
                  <tr key={c.complaint_id}
                      className={`clickable${selectedId === c.complaint_id ? ' selected' : ''}`}
                      onClick={() => { setSelectedId(c.complaint_id); setMessage(null); }}>
                    <td>
                      <button type="button" className="row-btn" onClick={() => setSelectedId(c.complaint_id)}>
                        <div className="cell-title">{c.title}</div>
                      </button>
                      <div className="cell-sub">
                        {regNo(c.complaint_id)}, {c.ward_name}
                        <span className={`prio ${c.priority}`} style={{ marginLeft: 10 }}>{PRIORITY_LABEL[c.priority]}</span>
                      </div>
                    </td>
                    {isAdmin && <td className="small">{c.dept_name ?? 'Unassigned'}</td>}
                    <td><span className={`tag ${c.status}`}>{STATUS_LABEL[c.status]}</span></td>
                    <td><Deadline filedAt={c.filed_at} deadline={c.sla_deadline} /></td>
                    <td className="right">{1 + Number(c.duplicate_count || 0)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {complaints === null && <p className="empty">Loading the queue</p>}
            {complaints && visible.length === 0 && (
              <p className="empty">No grievances match this filter.</p>
            )}
          </div>
        </section>

        <aside className="panel detail">
          {selectedId
            ? <Detail key={selectedId} id={selectedId} onChanged={onChanged} onClose={() => setSelectedId(null)} />
            : <Guide />}
        </aside>
      </div>
    </>
  );
}

function Guide() {
  return (
    <div className="panel-body">
      <h2>Select a grievance</h2>
      <p className="muted" style={{ marginTop: 8 }}>Choosing a row opens it here. From this panel you can:</p>
      <ul style={{ margin: '12px 0 0', paddingLeft: 20, lineHeight: 1.7 }}>
        <li>read the full description and its history</li>
        <li>see earlier complaints from the same ward that describe the same problem, matched by meaning rather than exact words</li>
        <li>join a repeat report to the earlier one, so the problem is fixed once</li>
        <li>start work on it, or mark it resolved</li>
      </ul>
      <p className="small muted" style={{ marginTop: 16 }}>
        The Reports column counts the grievance itself plus every repeat report already joined to it.
      </p>
    </div>
  );
}

function Detail({ id, onChanged, onClose }) {
  const [data, setData] = useState(null);
  const [matches, setMatches] = useState(null);
  const [confirming, setConfirming] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    fetch(`/api/complaints/${id}`).then((r) => r.json()).then(setData);
    fetch(`/api/complaints/${id}/duplicates?threshold=0.5`)
      .then((r) => (r.ok ? r.json() : { candidates: [] }))
      .then((d) => setMatches(d.candidates));
  }, [id]);

  async function setStatus(status, doneText) {
    setBusy(true);
    setError('');
    const res = await fetch(`/api/complaints/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status }),
    });
    const body = await res.json();
    setBusy(false);
    if (!res.ok) { setError(body.error); return; }
    onChanged(doneText);
    if (status === 'RESOLVED') onClose();
    else fetch(`/api/complaints/${id}`).then((r) => r.json()).then(setData);
  }

  async function join(parent) {
    setBusy(true);
    setError('');
    const res = await fetch(`/api/complaints/${id}/duplicates`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ parentId: parent.candidate_id, similarity: Number(parent.similarity) }),
    });
    const body = await res.json();
    setBusy(false);
    if (!res.ok) { setError(body.error); setConfirming(null); return; }
    onChanged(`Grievance ${regNo(id)} was joined to ${regNo(parent.candidate_id)}. It will be fixed once, as part of ${regNo(parent.candidate_id)}, and the citizen who lodged it can follow it there.`);
    onClose();
  }

  if (!data) return <p className="empty">Loading grievance {regNo(id)}</p>;
  const c = data.complaint;
  const closed = ['RESOLVED', 'MERGED'].includes(c.status);

  return (
    <div className="panel-body">
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'flex-start' }}>
        <div>
          <div className="cell-sub">Registration no. {regNo(c.complaint_id)}</div>
          <h2 style={{ marginTop: 2 }}>{c.title}</h2>
        </div>
        <span className={`tag ${c.status}`}>{STATUS_LABEL[c.status]}</span>
      </div>

      <p className="desc">{c.description}</p>

      <dl>
        <dt>Reported by</dt><dd>{c.filed_by}</dd>
        <dt>Ward</dt><dd>{c.ward_name}</dd>
        <dt>Department</dt><dd>{c.dept_name ?? 'Not yet assigned'}</dd>
        <dt>Reported</dt><dd>{formatDateTime(c.filed_at)}</dd>
        <dt>Urgency</dt><dd><span className={`prio ${c.priority}`}>{PRIORITY_LABEL[c.priority]}</span></dd>
        {!closed && (<><dt>Deadline</dt><dd><Deadline filedAt={c.filed_at} deadline={c.sla_deadline} /></dd></>)}
        {c.duplicate_count > 0 && (<><dt>Repeat reports</dt><dd>{c.duplicate_count} joined to this one</dd></>)}
      </dl>

      {!closed && (
        <div className="actions">
          {c.status !== 'IN_PROGRESS' && (
            <button type="button" className="btn secondary small" disabled={busy}
                    onClick={() => setStatus('IN_PROGRESS', `You started work on grievance ${regNo(id)}.`)}>
              Start work
            </button>
          )}
          <button type="button" className="btn go small" disabled={busy}
                  onClick={() => setStatus('RESOLVED', `Grievance ${regNo(id)} was marked resolved.`)}>
            Mark resolved
          </button>
        </div>
      )}
      {error && <p className="error-text" role="alert">{error}</p>}

      {!closed && (
        <>
          <h3 className="section-title">Is this a repeat of an earlier report?</h3>
          <p className="section-note">
            Earlier grievances from {c.ward_name}, compared by what they describe rather
            than the exact words used. If one is the same problem, join this grievance to it.
          </p>
          {matches === null && <p className="small muted">Checking earlier reports</p>}
          {matches?.length === 0 && (
            <p className="small muted">No earlier report from this ward looks like the same problem.</p>
          )}
          {matches?.map((m) => {
            const v = verdict(Number(m.similarity));
            const pct = Math.round(Number(m.similarity) * 100);
            const canJoin = m.candidate_status !== 'RESOLVED';
            return (
              <div className="match" key={m.candidate_id}>
                <div className="match-head">
                  <div>
                    <div className="cell-title">{m.candidate_title}</div>
                    <div className="cell-sub">{regNo(m.candidate_id)}</div>
                    <span className={`tag ${m.candidate_status}`} style={{ marginTop: 4 }}>
                      {STATUS_LABEL[m.candidate_status]}
                    </span>
                  </div>
                  {canJoin && (confirming === m.candidate_id ? (
                    <span style={{ display: 'flex', gap: 6 }}>
                      <button type="button" className="btn small" disabled={busy} onClick={() => join(m)}>
                        Confirm join
                      </button>
                      <button type="button" className="btn secondary small" onClick={() => setConfirming(null)}>
                        Cancel
                      </button>
                    </span>
                  ) : (
                    <button type="button" className="btn secondary small" onClick={() => setConfirming(m.candidate_id)}>
                      Join to this one
                    </button>
                  ))}
                </div>
                <div className={`meter${v.strong ? ' strong' : ''}`}>
                  <span className="track" aria-hidden="true"><span style={{ width: `${pct}%` }} /></span>
                  <strong>{pct}%</strong>
                  <span className="verdict">{v.text}</span>
                </div>
                {!canJoin && (
                  <p className="small muted" style={{ marginTop: 6 }}>
                    Already resolved. If the problem is back, treat this as a new grievance.
                  </p>
                )}
              </div>
            );
          })}
        </>
      )}

      <h3 className="section-title">Progress</h3>
      <RouteRail compact status={c.status} detail={{ department: c.dept_name }} />

      {data.history?.length > 0 && (
        <>
          <h3 className="section-title">History</h3>
          <ul className="timeline">
            {data.history.map((h) => (
              <li key={h.changed_at}>
                <time dateTime={h.changed_at}>{formatDateTime(h.changed_at)}</time>
                <span>
                  {STATUS_LABEL[h.new_status]}
                  {h.changed_by && h.changed_by !== 'system' ? `, by ${h.changed_by}` : ''}
                </span>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}
