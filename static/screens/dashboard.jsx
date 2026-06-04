// Jobhunt — Dashboard

// ── helpers ──────────────────────────────────────────────────────────────────

function fitColor(score) {
  if (score >= 70) return 'var(--st-offer)';
  if (score >= 40) return 'var(--st-screening)';
  return 'var(--fg-faint)';
}

function Card({ title, hint, children, action }) {
  return (
    <div style={{ background: 'var(--bg-elev)', border: '1px solid var(--border)', borderRadius: 'var(--r-2)', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '10px 12px', borderBottom: '1px solid var(--border-faint)', display: 'flex', alignItems: 'center', gap: 8 }}>
        <span style={{ fontSize: 12, fontWeight: 500, color: 'var(--fg-strong)' }}>{title}</span>
        {hint && <span style={{ marginLeft: 'auto', fontSize: 11, color: 'var(--fg-faint)', fontFamily: 'var(--font-mono)' }}>{hint}</span>}
        {action && <span style={{ marginLeft: hint ? 8 : 'auto' }}>{action}</span>}
      </div>
      <div style={{ flex: 1 }}>{children}</div>
    </div>
  );
}

function CardRow({ children, onClick }) {
  return (
    <div onClick={onClick} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 12px', borderBottom: '1px solid var(--border-faint)', cursor: onClick ? 'pointer' : 'default', fontSize: 12.5, minWidth: 0 }}
      onMouseEnter={e => { if (onClick) e.currentTarget.style.background = 'var(--bg-hover)'; }}
      onMouseLeave={e => { if (onClick) e.currentTarget.style.background = 'transparent'; }}>
      {children}
    </div>
  );
}

// ── Zone 1: Top opportunities ─────────────────────────────────────────────────

function FitOpportunityCard({ job, onSelect }) {
  const salary = fmtSalary(job);
  const score = job.fit?.score;
  return (
    <div style={{ background: 'var(--bg-elev)', border: '1px solid var(--border)', borderRadius: 'var(--r-2)', padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 8 }}>
        <div style={{ minWidth: 0 }}>
          <div style={{ fontWeight: 600, fontSize: 13, color: 'var(--fg-strong)', marginBottom: 2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{job.company || '—'}</div>
          <div style={{ fontSize: 12, color: 'var(--fg-mute)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{job.title || '—'}</div>
        </div>
        <div style={{ flexShrink: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 1 }}>
          <div style={{ fontSize: 20, fontWeight: 700, color: fitColor(score), fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>{score}</div>
          <div style={{ fontSize: 9, color: 'var(--fg-faint)', textTransform: 'uppercase', letterSpacing: '.04em' }}>fit</div>
        </div>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
        {job.workMode && <span style={{ fontSize: 11, padding: '1px 6px', borderRadius: 3, background: 'var(--bg-elev-2)', border: '1px solid var(--border)', color: 'var(--fg-mute)' }}>{job.workMode}</span>}
        {job.location && <span style={{ fontSize: 11, color: 'var(--fg-faint)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{job.location}</span>}
        {salary && <span style={{ fontSize: 11, color: 'var(--fg-mute)', marginLeft: 'auto', flexShrink: 0 }}>{salary}</span>}
      </div>
      <Btn size="sm" kind="ghost" onClick={() => onSelect && onSelect(job.id)} style={{ alignSelf: 'flex-end', marginTop: 2 }}>View →</Btn>
    </div>
  );
}

function TopOpportunities({ jobs, onSelectJob }) {
  const saved = jobs.filter(j => j.status === 'saved');
  const withScore = saved.filter(j => j.fit?.score != null).sort((a, b) => b.fit.score - a.fit.score).slice(0, 4);

  if (saved.length === 0) {
    return (
      <div style={{ background: 'var(--bg-elev)', border: '1px solid var(--border)', borderRadius: 'var(--r-2)', padding: '24px', textAlign: 'center', color: 'var(--fg-mute)', fontSize: 13 }}>
        <div style={{ fontSize: 24, marginBottom: 8 }}>📋</div>
        <div style={{ fontWeight: 500, color: 'var(--fg)', marginBottom: 4 }}>No saved jobs yet</div>
        <div>Use the Chrome extension or Add Job URL to capture your first job posting.</div>
      </div>
    );
  }

  if (withScore.length === 0) {
    return (
      <div style={{ background: 'var(--bg-elev)', border: '1px solid var(--border)', borderRadius: 'var(--r-2)', padding: '20px 24px' }}>
        <div style={{ fontWeight: 500, fontSize: 13, marginBottom: 4 }}>Run AI extraction to see your best opportunities</div>
        <div style={{ fontSize: 12, color: 'var(--fg-mute)' }}>{saved.length} saved job{saved.length !== 1 ? 's' : ''} — fit scores will appear here once extracted. Use <strong>Run AI extraction</strong> in the toolbar above.</div>
      </div>
    );
  }

  return (
    <div style={{ display: 'grid', gridTemplateColumns: `repeat(${Math.min(withScore.length, 4)}, 1fr)`, gap: 10 }}>
      {withScore.map(j => <FitOpportunityCard key={j.id} job={j} onSelect={onSelectJob} />)}
    </div>
  );
}

// ── Zone 2a: Pipeline funnel ──────────────────────────────────────────────────

function PipelineFunnel({ metrics, onNavigate, onNavigateToView }) {
  const stages = [
    { key: 'saved',     label: 'Saved',     count: metrics.saved || 0,     color: 'var(--st-saved)' },
    { key: 'applied',   label: 'Applied',   count: metrics.applied || 0,   color: 'var(--st-applied)' },
    { key: 'interview', label: 'Interview', count: metrics.interview || 0, color: 'var(--st-interview)' },
    { key: 'offer',     label: 'Offer',     count: metrics.offers || 0,    color: 'var(--st-offer)' },
  ];
  const maxCount = Math.max(...stages.map(s => s.count), 1);
  const total = stages.reduce((s, r) => s + r.count, 0);

  function goToStatus(key) {
    if (onNavigateToView) onNavigateToView(`status:${key}`);
    else if (onNavigate) onNavigate('jobs');
  }

  return (
    <Card title="Pipeline" hint={`${total} active`}>
      <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
        {stages.map(s => (
          <div key={s.key} className="jh-funnel__row" onClick={() => goToStatus(s.key)} title={`View ${s.label} jobs`}>
            <div className="jh-funnel__label">
              <span style={{ width: 7, height: 7, borderRadius: '50%', background: s.color, display: 'inline-block', marginRight: 6, flexShrink: 0 }} />
              {s.label}
            </div>
            <div className="jh-funnel__bar-track">
              <div className="jh-funnel__bar-fill" style={{ width: `${(s.count / maxCount) * 100}%`, background: s.color }} />
            </div>
            <div className="jh-funnel__count">{s.count}</div>
          </div>
        ))}
      </div>
      {(metrics.rejected > 0 || metrics.archived > 0) && (
        <div style={{ padding: '6px 14px 10px', display: 'flex', gap: 16, fontSize: 11, color: 'var(--fg-faint)' }}>
          {metrics.rejected > 0 && <span style={{ cursor: 'pointer' }} onClick={() => goToStatus('rejected')}>{metrics.rejected} rejected</span>}
          {metrics.archived > 0 && <span style={{ cursor: 'pointer' }} onClick={() => goToStatus('archived')}>{metrics.archived} archived</span>}
        </div>
      )}
    </Card>
  );
}

// ── Zone 2b: Action items ─────────────────────────────────────────────────────

function ActionItems({ jobs, metrics, onNavigate }) {
  const overdue = jobs.filter(j => j.nextAction && dueState(j.nextAction.dueDate) === 'overdue');
  const today   = jobs.filter(j => j.nextAction && dueState(j.nextAction.dueDate) === 'today');
  const qualityCount = summarizeQuality(jobs).counts.withIssues || 0;
  const failedCount = metrics.failedExtraction || 0;
  const dupeCount = metrics.duplicateGroups || 0;

  const items = [
    ...overdue.map(j => ({ kind: 'overdue', label: j.company || j.title, sub: dueLabel(j.nextAction.dueDate), nav: 'needs' })),
    ...today.map(j => ({ kind: 'today', label: j.company || j.title, sub: 'Due today', nav: 'needs' })),
    ...(failedCount > 0 ? [{ kind: 'warn', label: `${failedCount} extraction failure${failedCount !== 1 ? 's' : ''}`, sub: 'LLM Queue', nav: 'llm-queue' }] : []),
    ...(qualityCount > 0 ? [{ kind: 'info', label: `${qualityCount} data quality issue${qualityCount !== 1 ? 's' : ''}`, sub: 'Data Quality', nav: 'quality' }] : []),
    ...(dupeCount > 0 ? [{ kind: 'info', label: `${dupeCount} duplicate group${dupeCount !== 1 ? 's' : ''}`, sub: 'Duplicates', nav: 'duplicates' }] : []),
  ];

  const dotColor = { overdue: 'var(--st-rejected)', today: 'var(--st-screening)', warn: 'var(--st-screening)', info: 'var(--fg-faint)' };
  const shown = items.slice(0, 6);
  const overflow = items.length - shown.length;

  return (
    <Card title="Action items" hint={items.length > 0 ? `${items.length} item${items.length !== 1 ? 's' : ''}` : undefined}>
      {items.length === 0 ? (
        <div className="jh-empty" style={{ padding: '20px 16px' }}>
          <strong>Nothing needs attention today ✓</strong>
        </div>
      ) : (
        <>
          {shown.map((item, i) => (
            <CardRow key={i} onClick={() => onNavigate && onNavigate(item.nav)}>
              <span style={{ width: 7, height: 7, borderRadius: '50%', background: dotColor[item.kind], flexShrink: 0 }} />
              <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', color: 'var(--fg)' }}>{item.label}</span>
              <span style={{ fontSize: 11, color: 'var(--fg-faint)', flexShrink: 0 }}>{item.sub}</span>
            </CardRow>
          ))}
          {overflow > 0 && (
            <div style={{ padding: '6px 12px', fontSize: 11, color: 'var(--fg-faint)' }}>+ {overflow} more</div>
          )}
        </>
      )}
    </Card>
  );
}

function QualityCard({ label, value, issue, hint, warn }) {
  return (
    <button
      className="jh-metric"
      style={{ textAlign: 'left', cursor: 'pointer', borderColor: warn ? 'rgba(190,137,43,0.35)' : undefined }}
      onClick={() => { window.location.hash = issue === 'all' ? '#/quality' : `#/quality?issue=${issue}`; }}
    >
      <span className="jh-metric__label">{label}</span>
      <span className="jh-metric__value">{value}</span>
      <span className="jh-metric__delta">{hint}</span>
    </button>
  );
}

function QualityStrip({ jobs }) {
  const q = summarizeQuality(jobs).counts;
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, minmax(150px, 1fr))', gap: 8 }}>
      <QualityCard label="Data gaps" value={q.withIssues} issue="all" hint="active jobs" warn={q.withIssues > 0} />
      <QualityCard label="Needs recapture" value={q.needsRecapture} issue="recapture" hint="browser work" warn={q.needsRecapture > 0} />
      <QualityCard label="AI only" value={q.aiOnly} issue="aiOnly" hint="re-run extraction" warn={q.aiOnly > 0} />
      <QualityCard label="Missing salary" value={q.missingSalary} issue="salary" hint="review comp" warn={q.missingSalary > 0} />
    </div>
  );
}

// ── Zone 3: Operations strip ──────────────────────────────────────────────────

function OperationsStrip({ jobs, metrics, queueStats, onSelectJob, onProcessExtractions, processingExtractions, onNavigate }) {
  const recent = [...jobs].sort((a, b) => (b.capturedAt || '').localeCompare(a.capturedAt || '')).slice(0, 4);
  const outstanding = queueStats.totalOutstanding || 0;
  const failed = metrics.failedExtraction || 0;
  const pending = metrics.pendingExtraction || 0;

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1.6fr 1fr 1fr', gap: 10 }}>
      <Card title="Recent captures" hint={`${jobs.length} total`}>
        {recent.length === 0
          ? <div className="jh-empty" style={{ padding: 16 }}><span>No jobs captured yet.</span></div>
          : recent.map(j => (
            <CardRow key={j.id} onClick={() => onSelectJob && onSelectJob(j.id)}>
              <CompanyCell name={j.company} url={j.sourceUrl} />
              <span style={{ color: 'var(--fg)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flex: 1 }}>{j.title}</span>
              <span style={{ fontSize: 11, color: 'var(--fg-mute)', fontFamily: 'var(--font-mono)', flexShrink: 0 }}>{fmtCaptured(j.capturedAt)}</span>
            </CardRow>
          ))
        }
      </Card>

      <Card title="LLM Queue"
        hint={outstanding > 0 ? `${outstanding} outstanding` : 'idle'}
        action={outstanding > 0 ? <Btn size="sm" kind="accent" icon={<Icon.Sparkles size={11} />} onClick={onProcessExtractions} disabled={processingExtractions}>{processingExtractions ? 'Running…' : 'Process'}</Btn> : null}>
        <div style={{ padding: '10px 14px', display: 'flex', flexDirection: 'column', gap: 6 }}>
          {[
            { label: 'Pending', count: pending, color: 'var(--st-screening)' },
            { label: 'Running', count: queueStats.running || 0, color: 'var(--st-interview)' },
            { label: 'Failed',  count: failed, color: failed > 0 ? 'var(--st-rejected)' : 'var(--fg-faint)' },
          ].map(r => (
            <div key={r.label} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12 }}>
              <span style={{ color: 'var(--fg-mute)' }}>{r.label}</span>
              <span style={{ fontFamily: 'var(--font-mono)', color: r.count > 0 ? r.color : 'var(--fg-faint)' }}>{r.count}</span>
            </div>
          ))}
        </div>
      </Card>

      <Card title="Housekeeping">
        <div style={{ padding: '10px 14px', display: 'flex', flexDirection: 'column', gap: 4 }}>
          {[
            { label: 'Duplicates', count: metrics.duplicateGroups || 0, route: 'duplicates' },
            { label: 'Data quality', count: summarizeQuality(jobs).counts.withIssues || 0, route: 'quality' },
            { label: 'Sites due', count: metrics.sitesDue || 0, route: 'sites' },
          ].map(r => (
            <div key={r.label} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: 12, padding: '2px 0' }}>
              <span onClick={() => onNavigate && onNavigate(r.route)} style={{ color: 'var(--fg-mute)', cursor: 'pointer' }}
                onMouseEnter={e => e.currentTarget.style.color = 'var(--fg)'}
                onMouseLeave={e => e.currentTarget.style.color = 'var(--fg-mute)'}>{r.label}</span>
              <span style={{ fontFamily: 'var(--font-mono)', color: r.count > 0 ? 'var(--st-screening)' : 'var(--fg-faint)' }}>{r.count}</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}

// ── Zone 4: Daily activity table ─────────────────────────────────────────────

function buildDailyActivity(jobs) {
  const byDate = {};

  function bump(iso, key) {
    if (!iso) return;
    const dt = new Date(iso);
    const d = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
    if (!byDate[d]) byDate[d] = { saved: 0, applied: 0, interview: 0, offer: 0, rejected: 0 };
    byDate[d][key]++;
  }

  for (const job of jobs) {
    bump(job.capturedAt, 'saved');
    for (const ev of (job.events || [])) {
      if (ev.kind === 'status' && ev.note) {
        const s = ev.note;
        if (s === 'applied' || s === 'interview' || s === 'offer' || s === 'rejected') {
          bump(ev.at, s);
        }
      }
    }
  }

  return Object.entries(byDate)
    .sort(([a], [b]) => b.localeCompare(a))
    .map(([date, counts]) => ({ date, ...counts }));
}

const ACTIVITY_COLS = [
  { key: 'saved',     label: 'Saved',     color: 'var(--st-saved)' },
  { key: 'applied',   label: 'Applied',   color: 'var(--st-applied)' },
  { key: 'interview', label: 'Interview', color: 'var(--st-interview)' },
  { key: 'offer',     label: 'Offer',     color: 'var(--st-offer)' },
  { key: 'rejected',  label: 'Rejected',  color: 'var(--st-rejected)' },
];

function DailyActivityTable({ jobs }) {
  const [expanded, setExpanded] = React.useState(false);
  const rows = buildDailyActivity(jobs);
  const visible = expanded ? rows : rows.slice(0, 14);
  const totals = ACTIVITY_COLS.reduce((acc, c) => { acc[c.key] = rows.reduce((s, r) => s + r[c.key], 0); return acc; }, {});

  if (rows.length === 0) return null;

  const thStyle = { padding: '6px 12px', fontSize: 11, fontWeight: 500, color: 'var(--fg-mute)', textAlign: 'right', borderBottom: '1px solid var(--border)', whiteSpace: 'nowrap', background: 'var(--bg-elev)' };
  const tdStyle = { padding: '5px 12px', fontSize: 12, fontVariantNumeric: 'tabular-nums', textAlign: 'right', borderBottom: '1px solid var(--border-faint)', color: 'var(--fg-mute)' };

  function cellVal(n) {
    return n > 0 ? <span style={{ color: 'var(--fg)', fontWeight: 500 }}>{n}</span> : <span style={{ color: 'var(--fg-faint)' }}>—</span>;
  }

  return (
    <Card title="Daily activity" hint={`${rows.length} active day${rows.length !== 1 ? 's' : ''}`}>
      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', tableLayout: 'fixed' }}>
          <colgroup>
            <col style={{ width: '120px' }} />
            {ACTIVITY_COLS.map(c => <col key={c.key} />)}
          </colgroup>
          <thead>
            <tr>
              <th style={{ ...thStyle, textAlign: 'left' }}>Date</th>
              {ACTIVITY_COLS.map(c => (
                <th key={c.key} style={thStyle}>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                    <span style={{ width: 6, height: 6, borderRadius: '50%', background: c.color, display: 'inline-block' }} />
                    {c.label}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {visible.map(row => (
              <tr key={row.date}>
                <td style={{ ...tdStyle, textAlign: 'left', color: 'var(--fg)', fontFamily: 'var(--font-mono)', fontSize: 11.5 }}>{fmtDate(row.date)}</td>
                {ACTIVITY_COLS.map(c => <td key={c.key} style={tdStyle}>{cellVal(row[c.key])}</td>)}
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr>
              <td style={{ ...tdStyle, borderTop: '1px solid var(--border)', borderBottom: 'none', color: 'var(--fg-mute)', fontSize: 11, fontWeight: 500 }}>Total</td>
              {ACTIVITY_COLS.map(c => (
                <td key={c.key} style={{ ...tdStyle, borderTop: '1px solid var(--border)', borderBottom: 'none', fontWeight: 500, color: totals[c.key] > 0 ? 'var(--fg)' : 'var(--fg-faint)' }}>
                  {totals[c.key] > 0 ? totals[c.key] : '—'}
                </td>
              ))}
            </tr>
          </tfoot>
        </table>
      </div>
      {rows.length > 14 && (
        <div style={{ padding: '6px 12px', fontSize: 11, color: 'var(--fg-faint)', cursor: 'pointer', borderTop: '1px solid var(--border-faint)' }}
          onClick={() => setExpanded(e => !e)}>
          {expanded ? '▲ Show less' : `▼ Show all ${rows.length} days`}
        </div>
      )}
    </Card>
  );
}

// ── Main ──────────────────────────────────────────────────────────────────────

function DashboardPage({ onSelectJob, onProcessExtractions, processingExtractions, onNavigate, onNavigateToView }) {
  const jobs = window.JH_JOBS || [];
  const metrics = window.JH_METRICS || {};
  const queueStats = window.JH_QUEUE_STATS || {};

  return (
    <div style={{ padding: '16px 16px 24px', overflow: 'auto', flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', gap: 14 }}>

      {/* Zone 1: Top opportunities */}
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--fg-mute)', marginBottom: 8 }}>Top opportunities</div>
        <TopOpportunities jobs={jobs} onSelectJob={onSelectJob} />
      </div>

      {/* Zone 2: Pipeline + Actions */}
      <div style={{ display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 10 }}>
        <PipelineFunnel metrics={metrics} onNavigate={onNavigate} onNavigateToView={onNavigateToView} />
        <ActionItems jobs={jobs} metrics={metrics} onNavigate={onNavigate} />
      </div>

      {/* Zone 3: Operations */}
      <OperationsStrip jobs={jobs} metrics={metrics} queueStats={queueStats} onSelectJob={onSelectJob} onProcessExtractions={onProcessExtractions} processingExtractions={processingExtractions} onNavigate={onNavigate} />

      <QualityStrip jobs={jobs} />

      {/* Zone 4: Daily activity */}
      <DailyActivityTable jobs={jobs} />

    </div>
  );
}

Object.assign(window, { DashboardPage });
