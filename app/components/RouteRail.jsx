// The route a complaint travels. Used on the landing page to explain the
// service, and on every complaint to show where it currently is.

const STOPS = ['Lodged', 'Checked for repeats', 'Sent to department', 'Resolved'];

const EXPLAIN = [
  'You describe the problem in your own words.',
  'It is compared by meaning with earlier reports from your ward.',
  'It goes to the department that fixed similar problems before.',
  'The department has a fixed number of hours to resolve it.',
];

// Stops are numbered 0-3. For each status:
//   done    - how many stops are complete (0 .. done-1)
//   current - the stop it is waiting at, if any
//   alert   - a stop shown in red
//   merged  - a stop where the complaint left the route
//   notes   - short text under particular stops
function stateFor(status, d = {}) {
  const dept = d.department || 'Department assigned';
  switch (status) {
    case 'OPEN':
      return { done: 1, current: 1, notes: { 1: 'Waiting to be checked' } };
    case 'ROUTED':
      return { done: 3, current: 3, notes: { 2: dept, 3: "In the department's queue" } };
    case 'IN_PROGRESS':
      return { done: 3, current: 3, notes: { 2: dept, 3: 'Work has started' } };
    case 'ESCALATED':
      return { done: 3, alert: 3, notes: { 2: dept, 3: 'Past its deadline' } };
    case 'RESOLVED':
      return { done: 4, notes: { 2: dept, 3: d.resolvedOn } };
    case 'MERGED':
      return { done: 1, merged: 1, notes: { 1: d.mergedInto ? `Joined to ${d.mergedInto}` : 'Repeat report' } };
    default:
      return { done: 0, notes: {} };
  }
}

export default function RouteRail({ status, detail, explain = false, compact = false }) {
  const s = explain ? { done: 4, notes: {} } : stateFor(status, detail);

  // The yellow line runs from the first stop to the furthest stop touched.
  const furthest = Math.max(s.done - 1, s.current ?? -1, s.alert ?? -1, s.merged ?? -1, 0);
  const width = (furthest / (STOPS.length - 1)) * 75;

  return (
    <div className={`rail${compact ? ' compact' : ''}`} role="list" aria-label="Progress of the grievance">
      <span className="progress" style={{ width: `${width}%` }} aria-hidden="true" />
      {STOPS.map((name, i) => {
        let cls = '';
        if (s.merged === i) cls = 'merged';
        else if (s.alert === i) cls = 'alert';
        else if (s.current === i) cls = 'current';
        else if (i < s.done) cls = 'done';
        const note = explain ? EXPLAIN[i] : s.notes[i];
        return (
          <div key={name} role="listitem" className={`step ${cls}`} aria-current={s.current === i ? 'step' : undefined}>
            <span className="stop">{i + 1}</span>
            <div className="stop-name">{name}</div>
            {note && <div className="stop-note">{note}</div>}
          </div>
        );
      })}
    </div>
  );
}
