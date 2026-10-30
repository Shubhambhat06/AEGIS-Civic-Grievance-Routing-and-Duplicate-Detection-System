'use client';

// Citizen portal: file a complaint and track the ones already filed.
// If a complaint was merged as a duplicate, this page shows the parent
// complaint's status so the citizen can still follow progress.

import { useEffect, useState } from 'react';

export default function CitizenPage() {
  const [complaints, setComplaints] = useState([]);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [priority, setPriority] = useState('MEDIUM');
  const [message, setMessage] = useState(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    const res = await fetch('/api/complaints');
    if (res.ok) {
      const data = await res.json();
      setComplaints(data.complaints);
    }
  }

  useEffect(() => {
    load();
  }, []);

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);

    const res = await fetch('/api/complaints', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, description, priority }),
    });

    const data = await res.json();
    setBusy(false);

    if (!res.ok) {
      setMessage({ type: 'error', text: data.error });
      return;
    }

    setMessage({ type: 'success', text: `Complaint #${data.complaintId} submitted.` });
    setTitle('');
    setDescription('');
    load();
  }

  return (
    <>
      <h1>My complaints</h1>
      <p className="sub">File a new issue or check the status of an existing one.</p>

      <div className="row">
        <section>
          <h2>File a complaint</h2>
          <form onSubmit={handleSubmit}>
            <label htmlFor="title">Title</label>
            <input
              id="title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Large pothole near the bus stop"
              required
            />

            <label htmlFor="description">What is the problem?</label>
            <textarea
              id="description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Describe the issue and where exactly it is."
              required
            />

            <label htmlFor="priority">How urgent is it?</label>
            <select id="priority" value={priority} onChange={(e) => setPriority(e.target.value)}>
              <option value="LOW">Low</option>
              <option value="MEDIUM">Medium</option>
              <option value="HIGH">High</option>
              <option value="CRITICAL">Critical</option>
            </select>

            <button type="submit" disabled={busy}>
              {busy ? 'Submitting...' : 'Submit complaint'}
            </button>

            {message && (
              <p className={message.type === 'error' ? 'error' : 'success'}>{message.text}</p>
            )}
          </form>
        </section>

        <section>
          <h2>Status</h2>
          {complaints.length === 0 ? (
            <p className="sub">You have not filed any complaints yet.</p>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Title</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {complaints.map((c) => (
                  <tr key={c.complaint_id}>
                    <td>{c.complaint_id}</td>
                    <td>
                      {c.title}
                      {c.parent_complaint_id && (
                        <div className="sub" style={{ fontSize: 12, margin: 0 }}>
                          Same issue as #{c.parent_complaint_id} &ldquo;{c.merged_into_title}
                          &rdquo; &mdash; now {c.merged_into_status}
                        </div>
                      )}
                    </td>
                    <td>
                      <span className="badge">{c.status}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      </div>
    </>
  );
}
