// Small, dependency-free charts. Plain HTML bars where a bar is all that
// is needed, SVG only for the column chart.

// Horizontal bars, optionally stacked from several segments.
//   rows: [{ label, segments: [{ value, cls, title }], total }]
export function HBars({ rows, max, valueLabel = (r) => r.total }) {
  const top = max ?? Math.max(1, ...rows.map((r) => r.total));
  return (
    <div className="hbars">
      {rows.map((r) => (
        <div className="hbar-row" key={r.label}>
          <span className="hbar-label" title={r.label}>{r.label}</span>
          <span className="hbar-track" role="img" aria-label={`${r.label}: ${r.total}`}>
            {r.segments.map((s, i) =>
              s.value > 0 ? (
                <span key={i} className={s.cls} title={`${s.title}: ${s.value}`}
                      style={{ width: `${(s.value / top) * 100}%` }} />
              ) : null
            )}
          </span>
          <span className="hbar-value">{valueLabel(r)}</span>
        </div>
      ))}
    </div>
  );
}

export function Legend({ items }) {
  return (
    <div className="legend">
      {items.map((it) => (
        <span key={it.label}><i className={it.cls} />{it.label}</span>
      ))}
    </div>
  );
}

// Average resolution time against each department's own deadline.
// The black tick is the deadline; the bar turns red if it overshoots.
export function SlaBars({ rows }) {
  const top = Math.max(1, ...rows.map((r) => Math.max(r.avg_hours ?? 0, r.default_sla_hours))) * 1.08;
  return (
    <div className="hbars">
      {rows.map((r) => {
        const over = r.avg_hours != null && r.avg_hours > r.default_sla_hours;
        return (
          <div className="hbar-row" key={r.dept_name}>
            <span className="hbar-label" title={r.dept_name}>{r.dept_name}</span>
            <span className="sla-track" role="img"
                  aria-label={`${r.dept_name}: average ${r.avg_hours ?? 'n/a'} hours against a ${r.default_sla_hours} hour target`}>
              {r.avg_hours != null && (
                <span className={`fill${over ? ' over' : ''}`} style={{ width: `${(r.avg_hours / top) * 100}%` }} />
              )}
              <span className="target" style={{ left: `${(r.default_sla_hours / top) * 100}%` }}
                    title={`Target: ${r.default_sla_hours} h`} />
            </span>
            <span className="hbar-value">{r.avg_hours != null ? `${r.avg_hours} h` : 'none'}</span>
          </div>
        );
      })}
    </div>
  );
}

// One bar split into parts that add up to 100%.
export function StackBar({ parts }) {
  const total = parts.reduce((a, p) => a + p.value, 0) || 1;
  return (
    <>
      <div className="stackbar" role="img"
           aria-label={parts.map((p) => `${p.label} ${p.value}`).join(', ')}>
        {parts.map((p) =>
          p.value > 0 ? (
            <span key={p.label} className={p.cls} title={`${p.label}: ${p.value}`}
                  style={{ width: `${(p.value / total) * 100}%` }} />
          ) : null
        )}
      </div>
      <div className="legend">
        {parts.filter((p) => p.value > 0).map((p) => (
          <span key={p.label}><i className={p.cls} />{p.label} <strong>{p.value}</strong></span>
        ))}
      </div>
    </>
  );
}

// Vertical columns for a time series. Plain HTML, so the text stays at
// normal size however wide the panel is.
export function Columns({ data }) {
  const max = Math.max(1, ...data.map((d) => d.n));
  return (
    <div role="img" aria-label={data.map((d) => `${d.label}: ${d.n}`).join(', ')}>
      <div className="columns">
        {data.map((d) => (
          <div className="col" key={d.label}>
            {d.n > 0 && <span className="val">{d.n}</span>}
            <span className="bar" style={{ height: `${(d.n / max) * 100}%` }} />
          </div>
        ))}
      </div>
      <div className="col-labels" aria-hidden="true">
        {data.map((d, i) => (
          <span key={d.label}>{i % 2 === 0 || i === data.length - 1 ? d.label : ''}</span>
        ))}
      </div>
    </div>
  );
}
