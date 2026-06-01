// Jobhunt — Dashboard (compact, operational)

function DashboardPage({ onSelectJob, onProcessExtractions, processingExtractions }) {
  const M = window.JH_METRICS;
  const recent = [...window.JH_JOBS].sort((a, b) => new Date(b.capturedAt) - new Date(a.capturedAt)).slice(0, 5);
  const overdue = window.JH_JOBS.filter((j) => j.nextAction && (dueState(j.nextAction.dueDate) === "overdue" || dueState(j.nextAction.dueDate) === "today")).slice(0, 4);
  const failed = window.JH_JOBS.filter((j) => j.extraction.status === "fail").slice(0, 3);
  const quality = summarizeQuality(window.JH_JOBS || []);
  const q = quality.counts;

  return (
    <div style={{ padding: "16px 16px 24px", overflow: "auto", flex: 1 }}>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(8, 1fr)", gap: 8, marginBottom: 20 }}>
        <Metric label="Saved"        value={M.saved}        delta="" />
        <Metric label="Applied"      value={M.applied}      delta="" />
        <Metric label="Interviewing" value={M.interview} delta="active" />
        <Metric label="Offers"       value={M.offers}       delta="" emphasis={M.offers > 0} />
        <Metric label="Rejected"     value={M.rejected}     delta="" />
        <Metric label="Pending ext."  value={M.pendingExtraction} delta={M.failedExtraction + " failed"} warn={M.failedExtraction > 0} />
        <Metric label="Sites due"    value={M.sitesDue}     delta="" />
        <Metric label="Duplicates"   value={M.duplicateCandidates} delta={`${window.JH_DUPES.length} groups`} />
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1.4fr 1fr 1fr", gap: 12 }}>
        <Card title="Recent captures" hint="last 5">
          {recent.map((j) => (
            <CardRow key={j.id} onClick={() => onSelectJob && onSelectJob(j.id)}>
              <CompanyCell name={j.company} url={j.sourceUrl} />
              <span style={{ color: "var(--fg)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", minWidth: 0, flex: 1 }}>{j.title}</span>
              <StatusChip value={j.status} />
              <span className="col-mono" style={{ fontSize: 11, color: "var(--fg-mute)", width: 64, textAlign: "right" }}>{fmtCaptured(j.capturedAt)}</span>
            </CardRow>
          ))}
        </Card>

        <Card title="Overdue follow-ups" hint={overdue.length + " items"} accent="var(--st-rejected)">
          {overdue.length === 0 ? (
            <div className="jh-empty" style={{ padding: 16, display: "flex", flexDirection: "column", gap: 8, alignItems: "flex-start" }}>
              <span>No overdue actions. Nice.</span>
              <Btn size="sm" kind="ghost" onClick={() => onSelectJob && window.JH_TOAST && (window.JH_TOAST.show("Open a job to add follow-ups", "info"))}>Add follow-ups from job details</Btn>
            </div>
          ) :
            overdue.map((j) => (
              <CardRow key={j.id}>
                <span className="jh-due" data-state="overdue" style={{ width: 72 }}>
                  <Icon.Clock size={11} />{dueLabel(j.nextAction.dueDate)}
                </span>
                <span style={{ color: "var(--fg)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", flex: 1 }}>{j.company}</span>
                <Btn size="sm" kind="ghost" icon={<Icon.Check size={10} />} onClick={() => window.JH_API.completeAction(j.nextAction.id).catch((e) => window.JH_TOAST.show(e.message, "error"))}>Done</Btn>
              </CardRow>
            ))}
        </Card>

        <Card title="Extraction failures" hint={failed.length + " items"} accent="var(--st-screening)">
          {(M.pendingExtraction || M.failedExtraction) ? (
            <CardRow>
              <span style={{ color: "var(--fg)", flex: 1 }}>{M.pendingExtraction} pending · {M.failedExtraction} failed</span>
              <Btn size="sm" kind="accent" icon={<Icon.Sparkles size={11} />} onClick={onProcessExtractions} disabled={processingExtractions}>Process</Btn>
            </CardRow>
          ) : null}
          {failed.length === 0 ? <div className="jh-empty" style={{ padding: 16 }}><span>All clear.</span></div> :
            failed.map((j) => (
              <CardRow key={j.id}>
                <span className="jh-ex" data-state="fail"><span className="dot"></span></span>
                <span style={{ color: "var(--fg)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", flex: 1 }}>{j.company} · {j.title}</span>
                <Btn size="sm" kind="ghost" icon={<Icon.Refresh size={11} />} onClick={() => {
                  window.JH_API.api(`/api/jobs/${j.id}/extract`, { method: "POST" })
                    .then(() => {
                      window.JH_TOAST.show("Queued for re-extraction");
                      onProcessExtractions();
                    })
                    .catch(e => window.JH_TOAST.show(e.message, "error"));
                }}>Retry</Btn>
              </CardRow>
            ))}
        </Card>
      </div>

      <div style={{ marginTop: 12, display: "grid", gridTemplateColumns: "repeat(4, minmax(150px, 1fr))", gap: 8 }}>
        <QualityCard label="Data gaps" value={q.withIssues} issue="all" hint="active jobs" warn={q.withIssues > 0} />
        <QualityCard label="Needs recapture" value={q.needsRecapture} issue="recapture" hint="browser work" warn={q.needsRecapture > 0} />
        <QualityCard label="AI only" value={q.aiOnly} issue="aiOnly" hint="re-run extraction" warn={q.aiOnly > 0} />
        <QualityCard label="Missing salary" value={q.missingSalary} issue="salary" hint="review comp" warn={q.missingSalary > 0} />
      </div>
    </div>
  );
}

function QualityCard({ label, value, issue, hint, warn }) {
  return (
    <button
      className="jh-metric"
      style={{ textAlign: "left", cursor: "pointer", borderColor: warn ? "rgba(190,137,43,0.35)" : undefined }}
      onClick={() => { window.location.hash = issue === "all" ? "#/quality" : `#/quality?issue=${issue}`; }}
    >
      <span className="jh-metric__label">{label}</span>
      <span className="jh-metric__value">{value}</span>
      <span className="jh-metric__delta">{hint}</span>
    </button>
  );
}

function Metric({ label, value, delta, warn, emphasis }) {
  return (
    <div className="jh-metric" style={emphasis ? { borderColor: "var(--accent-border)", background: "var(--accent-bg)" } : undefined}>
      <span className="jh-metric__label">{label}</span>
      <span className="jh-metric__value">{value}</span>
      <span className="jh-metric__delta" style={warn ? { color: "var(--st-rejected)" } : undefined}>{delta}</span>
    </div>
  );
}

function Card({ title, hint, accent, children }) {
  return (
    <div style={{ background: "var(--bg-elev)", border: "1px solid var(--border)", borderRadius: "var(--r-2)", overflow: "hidden" }}>
      <div style={{ padding: "10px 12px", borderBottom: "1px solid var(--border-faint)", display: "flex", alignItems: "center", gap: 8 }}>
        {accent && <span style={{ width: 6, height: 6, borderRadius: 50, background: accent }}></span>}
        <span style={{ fontSize: 12, fontWeight: 500, color: "var(--fg-strong)" }}>{title}</span>
        <span style={{ marginLeft: "auto", fontSize: 11, color: "var(--fg-faint)", fontFamily: "var(--font-mono)" }}>{hint}</span>
      </div>
      <div style={{ display: "flex", flexDirection: "column" }}>
        {children}
      </div>
    </div>
  );
}

function CardRow({ children, onClick }) {
  return (
    <div
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", gap: 8, padding: "8px 12px",
        borderBottom: "1px solid var(--border-faint)", cursor: onClick ? "pointer" : "default",
        fontSize: 12.5, minWidth: 0,
      }}
      onMouseEnter={(e) => { if (onClick) e.currentTarget.style.background = "var(--bg-hover)"; }}
      onMouseLeave={(e) => { if (onClick) e.currentTarget.style.background = "transparent"; }}
    >
      {children}
    </div>
  );
}

Object.assign(window, { DashboardPage });
