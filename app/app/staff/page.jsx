'use client';

// Staff work queue.
//
// The queue is sorted by SLA urgency (breached first). Selecting a
// complaint runs the vector similarity search against earlier
// complaints in the same ward, and the staff member can merge an
// obvious duplicate with one click.

import { useEffect, useState } from 'react';

export default function StaffPage() {
  const [complaints, setComplaints] = useState([]);
  const [selected, setSelected] = useState(null);
  const [candidates, setCandidates] = useState([]);
  const [message, setMessage] = useState(null);

  async function loadQueue() {
    const res = await fetch('/api/complaints');
    if (res.ok) setComplaints((await res.json()).complaints);
  }

  useEffect(() => {
    loadQueue();
  }, []);

  async function inspect(complaint) {
    setSelected(complaint);
    setCandidates([]);
    setMessage(null);

    // threshold 0.5 so the staff member sees near-misses too and can
    // judge for themselves, rather than only automatic matches
    const res = await fetch(
      `/api/complaints/${complaint.complaint_id}/duplicates?threshold=0.5`
    );
    if (res.ok) setCandidates((await res.json()).candidates);
  }

  async function merge(parentId, similarity) {
    const res = await fetch(`/api/complaints/${selected.complaint_id}/duplicates`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ parentId, similarity }),
    });

    const data = await res.json();
    if (!res.ok) {
      setMessage({ type: 'error', text: data.error });
      return;
    }

    setMessage({
      type: 'success',
      text: `Complaint #${selected.complaint_id} merged into #${parentId}.`,
    });
    setSelected(null);
    setCandidates([]);
    loadQueue();
  }

  async function setStatus(complaintId, status) {
    const res = await fetch(`/api/complaints/${complaintId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status }),
    });

    const data = await res.json();
    if (!res.ok) {
      setMessage({ type: 'error', text: data.error });
      return;
    }
    loadQueue();
  }

  return (
    <>
      <h1>Work queue</h1>
      <p className="sub">Most urgent first. Breached SLA deadlines are shown in red.</p>

      {message && (
        <p className={message.type === 'error' ? 'error' : 'success'}>{message.text}</p>
      )}

      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Title</th>
            <th>Ward</th>
            <th>Priority</th>
            <th>Status</th>
            <th>Hours left</th>
            <th>Reports</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {complaints.map((c) => (
            <tr key={c.complaint_id}>
              <td>{c.complaint_id}</td>
              <td>{c.title}</td>
              <td>{c.ward_name}</td>
              <td>{c.priority}</td>
              <td>
                <span className="badge">{c.status}</span>
              </td>
              <td className={c.is_breached ? 'breached' : undefined}>
                {c.is_breached ? 'overdue' : Number(c.hours_remaining).toFixed(1)}
              </td>
              <td>{c.duplicate_count > 0 ? `+${c.duplicate_count}` : ''}</td>
              <td>
                <button
                  className="secondary"
                  style={{ marginTop: 0, padding: '4px 10px', fontSize: 13 }}
                  onClick={() => inspect(c)}
                >
                  Check duplicates
                </button>{' '}
                <button
                  className="secondary"
                  style={{ marginTop: 0, padding: '4px 10px', fontSize: 13 }}
                  onClick={() => setStatus(c.complaint_id, 'RESOLVED')}
                >
                  Resolve
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {selected && (
        <section className="card" style={{ marginTop: 24 }}>
          <h2 style={{ marginTop: 0 }}>
            Possible duplicates of #{selected.complaint_id}
          </h2>
          <p className="sub">{selected.title}</p>

          {candidates.length === 0 ? (
            <p className="sub">
              No similar complaints found in this ward. This looks like a new issue.
            </p>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Title</th>
                  <th>Status</th>
                  <th>Similarity</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {candidates.map((c) => (
                  <tr key={c.candidate_id}>
                    <td>{c.candidate_id}</td>
                    <td>{c.candidate_title}</td>
                    <td>
                      <span className="badge">{c.candidate_status}</span>
                    </td>
                    <td>{(Number(c.similarity) * 100).toFixed(0)}%</td>
                    <td>
                      <button
                        style={{ marginTop: 0, padding: '4px 10px', fontSize: 13 }}
                        onClick={() => merge(c.candidate_id, Number(c.similarity))}
                      >
                        Merge into this
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      )}
    </>
  );
}
