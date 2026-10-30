'use client';

// Admin dashboard. Reads the materialized view through /api/dashboard,
// which is restricted to the ADMIN role.

import { useEffect, useState } from 'react';

export default function AdminPage() {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    fetch('/api/dashboard')
      .then(async (res) => {
        if (!res.ok) {
          setError((await res.json()).error);
          return null;
        }
        return res.json();
      })
      .then(setData);
  }, []);

  if (error) return <p className="error">{error}</p>;
  if (!data) return <p className="sub">Loading...</p>;

  return (
    <>
      <h1>Department performance</h1>
      <p className="sub">
        Resolution times and SLA breach rates across all departments.
      </p>

      <table>
        <thead>
          <tr>
            <th>Department</th>
            <th>Total</th>
            <th>Open</th>
            <th>Resolved</th>
            <th>Escalated</th>
            <th>Avg hours</th>
            <th>SLA breach %</th>
          </tr>
        </thead>
        <tbody>
          {data.departments.map((d) => (
            <tr key={d.dept_name}>
              <td>{d.dept_name}</td>
              <td>{d.total_complaints}</td>
              <td>{d.open_count}</td>
              <td>{d.resolved_count}</td>
              <td>{d.escalated_count}</td>
              <td>{d.avg_resolution_hours ?? '-'}</td>
              <td>{d.sla_breach_pct ?? '-'}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <h2>Most-duplicated issues</h2>
      <p className="sub">
        One real problem, reported many times. The number is how many extra
        reports were folded into it.
      </p>
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Title</th>
            <th>Extra reports</th>
          </tr>
        </thead>
        <tbody>
          {data.duplicates.map((d) => (
            <tr key={d.complaint_id}>
              <td>{d.complaint_id}</td>
              <td>{d.title}</td>
              <td>{d.merged_count}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <h2>Complaints by ward</h2>
      <table>
        <thead>
          <tr>
            <th>Ward</th>
            <th>Complaints</th>
          </tr>
        </thead>
        <tbody>
          {data.wards.map((w) => (
            <tr key={w.ward_name}>
              <td>{w.ward_name}</td>
              <td>{w.complaint_count}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}
