import { formatHours, hoursUntil } from './format';

// Shows time left before the service deadline, with a bar for how much
// of the allowed time has already been used.
export default function Deadline({ filedAt, deadline, closed = false }) {
  if (closed || !deadline) return <span className="muted small">-</span>;

  const left = hoursUntil(deadline);
  const total = (new Date(deadline) - new Date(filedAt)) / 3600000 || 1;
  const used = Math.min(100, Math.max(0, ((total - left) / total) * 100));

  let cls = 'deadline';
  let text = `${formatHours(left)} left`;
  if (left < 0) { cls += ' late'; text = `${formatHours(left)} overdue`; }
  else if (left < 12) { cls += ' soon'; }

  return (
    <div className={cls}>
      <div className="text">{text}</div>
      <div className="bar" aria-hidden="true"><span style={{ width: `${left < 0 ? 100 : used}%` }} /></div>
    </div>
  );
}
