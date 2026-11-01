'use client';

// Citizen portal: lodge a grievance, and follow every grievance you have
// lodged along the route rail. A grievance that was joined to an
// earlier report shows that report's progress instead of going quiet.

import { useEffect, useState } from 'react';
import RouteRail from '@/components/RouteRail';
import Deadline from '@/components/Deadline';
import { STATUS_LABEL, PRIORITY_LABEL, formatDate, formatDateTime, regNo } from '@/components/format';

const PRIORITIES = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];

export default function CitizenPage() {
  const [complaints, setComplaints] = useState(null);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [priority, setPriority] = useState('MEDIUM');
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function load() {
    const res = await fetch('/api/complaints');
    if (res.ok) setComplaints((await res.json()).complaints);
    else setComplaints([]);
  }

  useEffect(() => { load(); }, []);

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError('');
    setResult(null);

    const res = await fetch('/api/complaints', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, description, priority }),
    });
    const data = await res.json();
    setBusy(false);

    if (!res.ok) {
      setError(data.error);
      return;
    }
    setResult(data);
    setTitle('');
    setDescription('');
    setPriority('MEDIUM');
    load();
  }

  return (
    <>
      <div className="page-head">
        <div>
          <h1>My grievances</h1>
          <p className="lede">Lodge a new grievance, or track one you have already lodged.</p>
        </div>
      </div>

      <div className="grid-main">
        <section className="panel">
          <div className="panel-head">
            <div>
              <h2>Lodge a grievance</h2>
              <p>It is registered under the ward on your account.</p>
            </div>
          </div>

          <form className="panel-body" onSubmit={handleSubmit}>
            <div className="field">
              <label htmlFor="title">What is the problem?</label>
              <span className="hint" id="title-hint">A short summary, for example "Street light not working outside the school".</span>
              <input id="title" type="text" aria-describedby="title-hint" value={title}
                     onChange={(e) => setTitle(e.target.value)} required minLength={5} maxLength={150} />
            </div>

            <div className="field">
              <label htmlFor="description">Describe it</label>
              <span className="hint" id="desc-hint">Where exactly is it, how long has it been like this, and is anyone at risk?</span>
              <textarea id="description" aria-describedby="desc-hint" value={description}
                        onChange={(e) => setDescription(e.target.value)} required minLength={15} />
            </div>

            <fieldset className="field" style={{ border: 0, padding: 0, margin: '18px 0 0' }}>
              <legend className="label-text">How urgent is it?</legend>
              <div className="choice four">
                {PRIORITIES.map((p) => (
                  <span key={p} style={{ display: 'contents' }}>
                    <input type="radio" id={`prio-${p}`} name="priority" value={p}
                           checked={priority === p} onChange={() => setPriority(p)} />
                    <label htmlFor={`prio-${p}`}>{PRIORITY_LABEL[p]}</label>
                  </span>
                ))}
              </div>
            </fieldset>

            <div className="field">
              <button type="submit" className="btn" disabled={busy}>
                {busy ? 'Submitting' : 'Submit grievance'}
              </button>
              {error && <p className="error-text" role="alert">{error}</p>}
            </div>

            {result && <Submitted result={result} />}
          </form>
        </section>

        <section className="panel">
          <div className="panel-head">
            <div>
              <h2>Grievances you have lodged</h2>
              <p>Select one to see where it is on its route.</p>
            </div>
          </div>
          {complaints === null && <p className="empty">Loading your grievances</p>}
          {complaints?.length === 0 && (
            <p className="empty">You have not lodged a grievance yet. Use the form to lodge your first one.</p>
          )}
          {complaints?.map((c) => (
            <ComplaintItem key={c.complaint_id} c={c} startOpen={result?.complaintId === c.complaint_id} />
          ))}
        </section>
      </div>
    </>
  );
}

function Submitted({ result }) {
  return (
    <div className="notice ok" role="status" style={{ marginTop: 20 }}>
      <h3>Grievance registered</h3>
      <p>Registration number <strong>{regNo(result.complaintId)}</strong>. Keep it to track your grievance.</p>
      {result.department ? (
        <p>
          Sent to <strong>{result.department}</strong>. They are due to resolve it
          by {formatDateTime(result.deadline)}.
        </p>
      ) : (
        <p>It is waiting to be checked and sent to a department.</p>
      )}
      {result.similarCount > 0 && (
        <p>
          {result.similarCount === 1 ? 'One similar report already exists' : `${result.similarCount} similar reports already exist`} in
          your ward. A department officer will check whether yours is the same problem, and if it is,
          join them so it is fixed once.
        </p>
      )}
    </div>
  );
}

function ComplaintItem({ c, startOpen }) {
  const [history, setHistory] = useState(null);

  async function onToggle(event) {
    if (event.currentTarget.open && history === null) {
      const res = await fetch(`/api/complaints/${c.complaint_id}`);
      setHistory(res.ok ? (await res.json()).history : []);
    }
  }

  const closed = ['RESOLVED', 'MERGED'].includes(c.status);

  return (
    <details className="complaint-item" open={startOpen} onToggle={onToggle}>
      <summary>
        <div>
          <div className="cell-title">{c.title}</div>
          <div className="cell-sub">{regNo(c.complaint_id)}, lodged {formatDate(c.filed_at)}</div>
          <div className="toggle"><span className="when-closed">Show progress</span><span className="when-open">Hide progress</span></div>
        </div>
        <span className={`tag ${c.status}`}>{STATUS_LABEL[c.status]}</span>
      </summary>

      <div className="complaint-body">
        <RouteRail compact status={c.status} detail={{
          department: c.dept_name,
          resolvedOn: c.resolved_at ? `on ${formatDate(c.resolved_at)}` : null,
          mergedInto: c.parent_complaint_id ? regNo(c.parent_complaint_id) : null,
        }} />

        {c.parent_complaint_id && (
          <div className="notice" style={{ marginTop: 18 }}>
            <p>
              This is the same problem as grievance {regNo(c.parent_complaint_id)},
              "{c.merged_into_title}", lodged earlier by someone in your ward.
              It is being handled once, there.
            </p>
            <p>
              Current status of {regNo(c.parent_complaint_id)}:{' '}
              <span className={`tag ${c.merged_into_status}`}>{STATUS_LABEL[c.merged_into_status]}</span>
            </p>
          </div>
        )}

        <div className="detail" style={{ position: 'static' }}>
          <dl>
            <dt>Ward</dt><dd>{c.ward_name}</dd>
            <dt>Department</dt><dd>{c.dept_name ?? 'Not yet assigned'}</dd>
            <dt>Urgency</dt><dd><span className={`prio ${c.priority}`}>{PRIORITY_LABEL[c.priority]}</span></dd>
            {!closed && (<><dt>Deadline</dt><dd><Deadline filedAt={c.filed_at} deadline={c.sla_deadline} /></dd></>)}
            {c.resolved_at && (<><dt>Resolved</dt><dd>{formatDateTime(c.resolved_at)}</dd></>)}
          </dl>
        </div>

        {history && history.length > 0 && (
          <>
            <h3 className="section-title">History</h3>
            <ul className="timeline">
              {history.map((h) => (
                <li key={h.changed_at}>
                  <time dateTime={h.changed_at}>{formatDateTime(h.changed_at)}</time>
                  <span>{STATUS_LABEL[h.new_status]}{h.remarks ? `. ${h.remarks}` : ''}</span>
                </li>
              ))}
            </ul>
          </>
        )}
      </div>
    </details>
  );
}
