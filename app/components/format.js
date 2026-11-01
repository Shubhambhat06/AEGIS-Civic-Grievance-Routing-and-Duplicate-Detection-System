// Plain-language labels and formatting shared by every page.

export const STATUS_LABEL = {
  OPEN: 'Received',
  ROUTED: 'With department',
  IN_PROGRESS: 'Being worked on',
  RESOLVED: 'Resolved',
  MERGED: 'Joined to an earlier report',
  ESCALATED: 'Overdue, escalated',
};

export const PRIORITY_LABEL = {
  LOW: 'Low',
  MEDIUM: 'Medium',
  HIGH: 'High',
  CRITICAL: 'Urgent',
};

const dateFmt = new Intl.DateTimeFormat('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
const dateTimeFmt = new Intl.DateTimeFormat('en-IN', {
  day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit', hour12: true,
});

export function formatDate(value) {
  return value ? dateFmt.format(new Date(value)) : '';
}

export function formatDateTime(value) {
  return value ? dateTimeFmt.format(new Date(value)) : '';
}

// "2 d 4 h" style durations, used for time left and time taken
export function formatHours(hours) {
  const h = Math.abs(Math.round(hours));
  if (h < 1) return 'under 1 h';
  if (h < 48) return `${h} h`;
  const d = Math.floor(h / 24);
  const rest = h % 24;
  return rest ? `${d} d ${rest} h` : `${d} d`;
}

export function hoursUntil(value) {
  return (new Date(value).getTime() - Date.now()) / 3600000;
}

// Registration number shown to people, in the style Indian grievance
// portals use: a prefix and a zero-padded serial. The database key stays
// the plain integer; this is presentation only.
export function regNo(id) {
  return `AEG/${String(id).padStart(5, '0')}`;
}
