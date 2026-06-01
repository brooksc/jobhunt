// Jobhunt — data quality dashboard

const QUALITY_STALE_DAYS = 21;

function hasValue(value) {
  const text = String(value ?? "").trim();
  return text !== "" && text !== "—" && text.toLowerCase() !== "unknown";
}

function isActionableJob(job) {
  return job.status !== "archived" && job.status !== "not_available" && !job.dataQualityReviewedAt;
}

function hasActionableStatus(job) {
  return job.status !== "archived" && job.status !== "not_available";
}

function qualityIssuesForJob(job) {
  const issues = [];
  if (!hasValue(job.company)) issues.push({ key: "company", label: "Missing company", severity: "high" });
  if (!hasValue(job.title)) issues.push({ key: "title", label: "Missing title", severity: "high" });
  if (!hasValue(job.location)) issues.push({ key: "location", label: "Missing location", severity: "high" });
  if (!hasValue(job.workMode)) issues.push({ key: "workMode", label: "Missing work mode", severity: "med" });
  if (!(job.salaryMin || job.salaryMax || job.salaryNote)) issues.push({ key: "salary", label: "Missing salary", severity: "med" });
  if (job.extraction?.status === "fail") issues.push({ key: "failed", label: "Extraction failed", severity: "high" });
  if (job.extraction?.status === "pending") issues.push({ key: "pending", label: "Extraction pending", severity: "med" });
  if ((job.rawByteSize || 0) < 1000) issues.push({ key: "shortRaw", label: "Short capture", severity: "med" });
  if ((job.cleanedByteSize || 0) < 700) issues.push({ key: "shortCleaned", label: "Short cleaned text", severity: "low" });
  if (job.capturedAt && daysFrom(job.capturedAt.slice(0, 10)) < -QUALITY_STALE_DAYS) {
    issues.push({ key: "stale", label: `Captured ${QUALITY_STALE_DAYS}+ days ago`, severity: "low" });
  }
  return issues;
}

function summarizeQuality(jobs) {
  const active = jobs.filter(isActionableJob);
  const reviewed = jobs.filter((j) => hasActionableStatus(j) && j.dataQualityReviewedAt);
  const excluded = jobs.filter((j) => !hasActionableStatus(j));
  const rows = active.map((job) => ({ job, issues: qualityIssuesForJob(job) })).filter((row) => row.issues.length > 0);
  const reviewedRows = reviewed.map((job) => ({ job, issues: qualityIssuesForJob(job) }));
  const needsRecapture = rows.filter((r) => needsBrowserRecapture(r.job, r.issues)).length;
  const aiOnly = rows.filter((r) => needsAiOnly(r.job, r.issues)).length;
  const counts = {
    active: active.length,
    excluded: excluded.length,
    reviewed: reviewed.length,
    withIssues: rows.length,
    missingLocation: rows.filter((r) => r.issues.some((i) => i.key === "location")).length,
    missingSalary: rows.filter((r) => r.issues.some((i) => i.key === "salary")).length,
    failed: rows.filter((r) => r.issues.some((i) => i.key === "failed")).length,
    pending: rows.filter((r) => r.issues.some((i) => i.key === "pending")).length,
    shortCapture: rows.filter((r) => r.issues.some((i) => i.key === "shortRaw" || i.key === "shortCleaned")).length,
    stale: rows.filter((r) => r.issues.some((i) => i.key === "stale")).length,
    needsRecapture,
    aiOnly,
  };
  return { rows, reviewedRows, counts };
}

function sourceLabel(job) {
  if (job.source) return job.source;
  try { return new URL(job.sourceUrl).hostname.replace(/^www\./, ""); } catch { return "Unknown"; }
}

function summarizeSiteHealth(jobs) {
  const groups = new Map();
  jobs.filter(isActionableJob).forEach((job) => {
    const site = sourceLabel(job);
    const issues = qualityIssuesForJob(job);
    const current = groups.get(site) || {
      site,
      total: 0,
      withIssues: 0,
      missingLocation: 0,
      missingSalary: 0,
      shortCapture: 0,
      failedOrPending: 0,
    };
    current.total += 1;
    if (issues.length) current.withIssues += 1;
    if (issues.some((i) => i.key === "location")) current.missingLocation += 1;
    if (issues.some((i) => i.key === "salary")) current.missingSalary += 1;
    if (issues.some((i) => i.key === "shortRaw" || i.key === "shortCleaned")) current.shortCapture += 1;
    if (issues.some((i) => i.key === "failed" || i.key === "pending")) current.failedOrPending += 1;
    groups.set(site, current);
  });
  return [...groups.values()]
    .map((site) => ({ ...site, issueRate: site.total ? site.withIssues / site.total : 0 }))
    .sort((a, b) => b.issueRate - a.issueRate || b.withIssues - a.withIssues || a.site.localeCompare(b.site))
    .slice(0, 8);
}

function sourceGuidance(site) {
  const text = String(site || "").toLowerCase();
  if (text.includes("microsoft")) return "Open the selected result detail; locations often live above the JD.";
  if (text.includes("levels")) return "Use the job detail pane/modal, not only the search list.";
  if (text.includes("builtin")) return "Wait for top badges and the full JD before capture.";
  if (text.includes("greenhouse") || text.includes("lever")) return "Capture the canonical detail page after all sections load.";
  if (text.includes("linkedin")) return "Open the full job detail and expand the description first.";
  return "Open the source page, expand hidden sections, then recapture.";
}

function issueColor(severity) {
  if (severity === "high") return "var(--st-rejected)";
  if (severity === "med") return "var(--st-screening)";
  return "var(--fg-mute)";
}

function issueSortScore(row) {
  const weights = { high: 100, med: 20, low: 5 };
  return row.issues.reduce((sum, issue) => sum + (weights[issue.severity] || 0), 0);
}

function issueKeys(issues) {
  return new Set(issues.map((issue) => issue.key));
}

function needsBrowserRecapture(job, issues) {
  const keys = issueKeys(issues);
  return keys.has("shortRaw") || keys.has("shortCleaned") || keys.has("stale") || ((keys.has("company") || keys.has("title")) && !job.selectedTextPresent);
}

function needsAiOnly(job, issues) {
  const keys = issueKeys(issues);
  return !needsBrowserRecapture(job, issues) && (keys.has("failed") || keys.has("pending") || keys.has("location") || keys.has("workMode") || keys.has("salary"));
}

function qualityHint(job, issues) {
  const keys = new Set(issues.map((issue) => issue.key));
  if (!job.capturedAt) return "No capture timestamp; recapture from the source page.";
  if (keys.has("shortRaw") && !job.selectedTextPresent) return "Capture is short and has no selected text; open the source JD and recapture after the full description is visible.";
  if (keys.has("shortRaw")) return "Raw capture is small; source page may have hidden or lazy-loaded JD text.";
  if (keys.has("shortCleaned")) return "Cleaned text is small; extraction may be working from a weak description.";
  if (keys.has("failed")) return job.extraction?.error ? `LLM failed: ${job.extraction.error}` : "LLM failed; show details in the queue or re-run extraction.";
  if (keys.has("pending")) return "Queued or waiting for extraction; run AI extraction from the queue.";
  if (keys.has("location") || keys.has("workMode")) return "Location/work mode missing after extraction; check whether the JD text contains it, then recapture or re-run AI.";
  if (keys.has("salary")) return "Salary was not extracted; many postings omit it, otherwise recapture/re-run AI.";
  if (keys.has("company") || keys.has("title")) return "Core metadata missing; source capture likely started from a search/listing page instead of a detail page.";
  if (keys.has("stale")) return "Capture is old; open the source page and check whether the job is still live.";
  return "Review capture diagnostics on the job detail panel.";
}

function openSourcePages(jobs) {
  const urls = [...new Set(jobs.map((job) => job.sourceUrl).filter(Boolean))];
  let opened = 0;
  urls.forEach((url) => {
    const a = document.createElement("a");
    a.href = url;
    a.target = "_blank";
    a.rel = "noopener";
    a.style.display = "none";
    document.body.appendChild(a);
    a.click();
    a.remove();
    opened++;
  });
  return opened;
}

function DataQualityPage({ onSelectJob, onSelectJobs, issue, setIssue }) {
  const validIssueKeys = new Set(["all", "reviewed", "recapture", "aiOnly", "location", "salary", "failed", "pending", "shortText", "stale"]);
  const filter = validIssueKeys.has(issue) ? issue : "all";
  const setFilter = (next) => setIssue?.(validIssueKeys.has(next) ? next : "all");
  const [confirmStatus, setConfirmStatus] = React.useState(null);
  const [busy, setBusy] = React.useState(false);
  const { rows, reviewedRows, counts } = summarizeQuality(window.JH_JOBS || []);
  const baseRows = filter === "reviewed" ? reviewedRows : rows;
  const filtered = baseRows
    .filter((row) => filter === "all" || (filter === "recapture"
      ? needsBrowserRecapture(row.job, row.issues)
      : filter === "aiOnly"
        ? needsAiOnly(row.job, row.issues)
        : filter === "reviewed"
          ? true
        : filter === "shortText"
      ? row.issues.some((issue) => issue.key === "shortRaw" || issue.key === "shortCleaned")
      : row.issues.some((issue) => issue.key === filter)))
    .sort((a, b) => issueSortScore(b) - issueSortScore(a) || new Date(b.job.capturedAt) - new Date(a.job.capturedAt));
  const visibleJobs = filtered.map((row) => row.job);
  const visibleJobIds = visibleJobs.map((job) => job.id);

  const filters = [
    ["all", "All issues", counts.withIssues],
    ["reviewed", "Reviewed", counts.reviewed],
    ["recapture", "Needs recapture", counts.needsRecapture],
    ["aiOnly", "AI only", counts.aiOnly],
    ["location", "Location", counts.missingLocation],
    ["salary", "Salary", counts.missingSalary],
    ["failed", "Failed", counts.failed],
    ["pending", "Pending", counts.pending],
    ["shortText", "Short capture", counts.shortCapture],
    ["stale", "Stale", counts.stale],
  ];

  function runForVisible(action) {
    if (visibleJobs.length === 0 || busy) return;
    setBusy(true);
    action()
      .finally(() => setBusy(false));
  }

  function reprocessVisible() {
    runForVisible(() => window.JH_API.bulkQueueLlm(visibleJobIds, "extract")
      .then(() => {
        window.JH_TOAST?.show(`${visibleJobIds.length} job${visibleJobIds.length !== 1 ? "s" : ""} queued for AI reprocessing`);
        return window.JH_REFRESH_UI_DATA?.();
      })
      .catch((e) => window.JH_TOAST?.show(e.message, "error")));
  }

  function updateVisibleStatus(status) {
    runForVisible(() => window.JH_API.bulkSetStatus(visibleJobIds, status)
      .then(() => {
        window.JH_TOAST?.show(`${visibleJobIds.length} job${visibleJobIds.length !== 1 ? "s" : ""} marked ${statusLabel(status)}`);
        setConfirmStatus(null);
        return window.JH_REFRESH_UI_DATA?.();
      })
      .catch((e) => window.JH_TOAST?.show(e.message, "error")));
  }

  function markVisibleReviewed() {
    runForVisible(() => window.JH_API.markDataQualityReviewed(visibleJobIds)
      .then(() => {
        window.JH_TOAST?.show(`${visibleJobIds.length} data quality row${visibleJobIds.length !== 1 ? "s" : ""} dismissed`);
        return window.JH_REFRESH_UI_DATA?.();
      })
      .catch((e) => window.JH_TOAST?.show(e.message, "error")));
  }

  function undoVisibleReviewed() {
    runForVisible(() => window.JH_API.clearDataQualityReviewed(visibleJobIds)
      .then(() => {
        window.JH_TOAST?.show(`${visibleJobIds.length} reviewed row${visibleJobIds.length !== 1 ? "s" : ""} restored`);
        return window.JH_REFRESH_UI_DATA?.();
      })
      .catch((e) => window.JH_TOAST?.show(e.message, "error")));
  }

  const siteHealth = summarizeSiteHealth(window.JH_JOBS || []);

  return (
    <div style={{ padding: "16px 16px 24px", overflow: "auto", flex: 1 }}>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(6, minmax(110px, 1fr))", gap: 8, marginBottom: 14 }}>
        <Metric label="Active jobs" value={counts.active} delta={`${counts.excluded} excluded`} />
        <Metric label="With gaps" value={counts.withIssues} delta="needs review" warn={counts.withIssues > 0} />
        <Metric label="No location" value={counts.missingLocation} delta="" warn={counts.missingLocation > 0} />
        <Metric label="No salary" value={counts.missingSalary} delta="" warn={counts.missingSalary > 0} />
        <Metric label="LLM issues" value={counts.failed + counts.pending} delta={`${counts.failed} failed`} warn={counts.failed > 0} />
        <Metric label="Short text" value={counts.shortCapture} delta={`${counts.reviewed} reviewed`} warn={counts.shortCapture > 0} />
      </div>

      <div style={{ background: "var(--bg-elev)", border: "1px solid var(--border)", borderRadius: "var(--r-2)", marginBottom: 12, overflow: "hidden" }}>
        <div style={{ padding: "10px 12px", borderBottom: "1px solid var(--border-faint)", display: "flex", alignItems: "center", gap: 8 }}>
          <Icon.Globe size={13} />
          <span style={{ fontSize: 12, fontWeight: 600, color: "var(--fg-strong)" }}>Site parsing health</span>
          <span style={{ marginLeft: "auto", fontSize: 11, color: "var(--fg-faint)" }}>worst active sources by data gaps</span>
        </div>
        {siteHealth.length === 0 ? (
          <div className="jh-empty" style={{ padding: 16 }}>No site parsing issues.</div>
        ) : (
          <div style={{ display: "grid", gridTemplateColumns: "1.2fr .5fr .7fr .7fr .7fr .8fr 1.8fr", gap: 8, padding: "8px 12px", fontSize: 12 }}>
            <span style={{ color: "var(--fg-mute)" }}>Source</span>
            <span style={{ color: "var(--fg-mute)", textAlign: "right" }}>Rows</span>
            <span style={{ color: "var(--fg-mute)", textAlign: "right" }}>Gap rate</span>
            <span style={{ color: "var(--fg-mute)", textAlign: "right" }}>Location</span>
            <span style={{ color: "var(--fg-mute)", textAlign: "right" }}>Salary</span>
            <span style={{ color: "var(--fg-mute)", textAlign: "right" }}>LLM/Text</span>
            <span style={{ color: "var(--fg-mute)" }}>Capture guidance</span>
            {siteHealth.map((site) => (
              <React.Fragment key={site.site}>
                <span className="jh-tag" style={{ width: "fit-content" }}>{site.site}</span>
                <span className="col-mono" style={{ textAlign: "right" }}>{site.withIssues}/{site.total}</span>
                <span className="col-mono" style={{ textAlign: "right", color: site.issueRate > 0.3 ? "var(--st-screening)" : "var(--fg-mute)" }}>{Math.round(site.issueRate * 100)}%</span>
                <span className="col-mono" style={{ textAlign: "right" }}>{site.missingLocation || "—"}</span>
                <span className="col-mono" style={{ textAlign: "right" }}>{site.missingSalary || "—"}</span>
                <span className="col-mono" style={{ textAlign: "right" }}>{site.failedOrPending + site.shortCapture || "—"}</span>
                <span className="col-mute">{sourceGuidance(site.site)}</span>
              </React.Fragment>
            ))}
          </div>
        )}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(2, minmax(220px, 1fr))", gap: 8, marginBottom: 12 }}>
        <button
          className="jh-metric"
          data-active={filter === "recapture" ? "true" : undefined}
          onClick={() => setFilter("recapture")}
          style={{ textAlign: "left", cursor: "pointer" }}
        >
          <span className="jh-metric__label">Browser recapture checklist</span>
          <span className="jh-metric__value">{counts.needsRecapture}</span>
          <span className="jh-metric__delta">short, stale, or weak captures</span>
        </button>
        <button
          className="jh-metric"
          data-active={filter === "aiOnly" ? "true" : undefined}
          onClick={() => setFilter("aiOnly")}
          style={{ textAlign: "left", cursor: "pointer" }}
        >
          <span className="jh-metric__label">AI re-run checklist</span>
          <span className="jh-metric__value">{counts.aiOnly}</span>
          <span className="jh-metric__delta">likely fixable without recapture</span>
        </button>
      </div>

      <div className="jh-toolbar" style={{ paddingLeft: 0, paddingRight: 0 }}>
        {filters.map(([key, label, count]) => (
          <button
            key={key}
            className="jh-filter"
            data-active={filter === key ? "true" : undefined}
            onClick={() => setFilter(key)}
          >
            <span className="label">{label}</span>
            <span className="val">{count}</span>
          </button>
        ))}
        <div style={{ marginLeft: "auto", color: "var(--fg-faint)", fontSize: 11.5 }}>
          Archived, unavailable, and reviewed jobs are excluded from gap counts.
        </div>
      </div>

      <div className="jh-toolbar" style={{ paddingLeft: 0, paddingRight: 0, borderTop: 0 }}>
        <span style={{ color: "var(--fg-mute)", fontSize: 12 }}>
          {visibleJobs.length} visible job{visibleJobs.length !== 1 ? "s" : ""}
        </span>
        <Btn
          size="sm"
          kind="ghost"
          icon={<Icon.External size={12} />}
          disabled={visibleJobs.length === 0 || busy}
          onClick={() => {
            const opened = openSourcePages(visibleJobs);
            window.JH_TOAST?.show(opened ? `Opened ${opened} source page${opened !== 1 ? "s" : ""}` : "No visible jobs have source pages", opened ? "success" : "error");
          }}
        >
          Open visible
        </Btn>
        <Btn
          size="sm"
          kind="ghost"
          icon={<Icon.Sparkles size={12} />}
          disabled={visibleJobs.length === 0 || busy}
          onClick={reprocessVisible}
        >
          Re-run AI
        </Btn>
        <Btn
          size="sm"
          kind="ghost"
          icon={<Icon.Check size={12} />}
          disabled={visibleJobs.length === 0 || busy}
          onClick={() => onSelectJobs?.(visibleJobIds)}
        >
          Select in Jobs
        </Btn>
        {filter === "reviewed" ? (
          <Btn
            size="sm"
            kind="ghost"
            icon={<Icon.Refresh size={12} />}
            disabled={visibleJobs.length === 0 || busy}
            onClick={undoVisibleReviewed}
          >
            Undo reviewed
          </Btn>
        ) : (
          <Btn
            size="sm"
            kind="ghost"
            icon={<Icon.Check size={12} />}
            disabled={visibleJobs.length === 0 || busy}
            onClick={markVisibleReviewed}
          >
            Dismiss visible
          </Btn>
        )}
        <Btn
          size="sm"
          kind="ghost"
          icon={<Icon.Archive size={12} />}
          disabled={visibleJobs.length === 0 || busy}
          onClick={() => setConfirmStatus("archived")}
        >
          Archive visible
        </Btn>
        <Btn
          size="sm"
          kind="ghost"
          icon={<Icon.X size={12} />}
          disabled={visibleJobs.length === 0 || busy}
          onClick={() => setConfirmStatus("not_available")}
        >
          Mark unavailable
        </Btn>
      </div>

      <div className="jh-tablewrap" style={{ marginTop: 8 }}>
        <table className="jh-table" style={{ tableLayout: "fixed" }}>
          <colgroup>
            <col style={{ width: 72 }} />
            <col style={{ width: 180 }} />
            <col />
            <col style={{ width: 250 }} />
            <col style={{ width: 310 }} />
            <col style={{ width: 115 }} />
            <col style={{ width: 115 }} />
            <col style={{ width: 130 }} />
          </colgroup>
          <thead>
            <tr>
              <th>ID</th>
              <th>Company</th>
              <th>Title</th>
              <th>Issues</th>
              <th>Likely cause</th>
              <th>Captured</th>
              <th>Processed</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan="8">
                  <div className="jh-empty">
                    <Icon.Check size={20} />
                    <strong>No data gaps in this view</strong>
                  </div>
                </td>
              </tr>
            ) : filtered.map(({ job, issues }) => (
              <tr
                key={job.id}
                tabIndex={0}
                role="row"
                onClick={() => onSelectJob?.(job.id)}
                onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onSelectJob?.(job.id); } }}
              >
                <td className="col-mono">#{job.jobNumber}</td>
                <td><CompanyCell name={job.company} url={job.sourceUrl} /></td>
                <td className="col-co" title={job.title}>{job.title}</td>
                <td>
                  <span style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
                    {issues.map((issue) => (
                      <span key={issue.key} className="jh-tag" style={{ borderColor: issueColor(issue.severity), color: issueColor(issue.severity) }}>
                        {issue.label}
                      </span>
                    ))}
                  </span>
                </td>
                <td className="col-mute" title={qualityHint(job, issues)}>{qualityHint(job, issues)}</td>
                <td className="col-mono" title={fmtDateTime(job.capturedAt)}>{fmtCaptured(job.capturedAt)}</td>
                <td className="col-mono" title={fmtDateTime(job.extraction?.at)}>{fmtCaptured(job.extraction?.at)}</td>
                <td onClick={(e) => e.stopPropagation()}>
                  <span style={{ display: "inline-flex", gap: 4 }}>
                    <Btn size="sm" kind="ghost" icon={<Icon.External size={11} />} title="Open source" aria-label="Open source" onClick={() => window.open(job.sourceUrl, "_blank")} />
                    <Btn size="sm" kind="ghost" icon={<Icon.Refresh size={11} />} title="Re-run extraction" aria-label="Re-run extraction" onClick={() => {
                      window.JH_API.rerunExtraction(job.id)
                        .then(() => window.JH_TOAST.show("Queued for re-extraction"))
                        .catch((e) => window.JH_TOAST.show(e.message, "error"));
                    }} />
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {confirmStatus && (
        <AppDialog
          title={confirmStatus === "archived" ? "Archive visible jobs?" : "Mark visible jobs unavailable?"}
          onClose={() => setConfirmStatus(null)}
          actions={[
            { label: "Cancel", kind: "ghost", onClick: () => setConfirmStatus(null) },
            {
              label: confirmStatus === "archived" ? "Archive" : "Mark unavailable",
              kind: "accent",
              onClick: () => updateVisibleStatus(confirmStatus),
              disabled: busy,
            },
          ]}
        >
          This will update {visibleJobs.length} currently visible job{visibleJobs.length !== 1 ? "s" : ""} in this Data Quality filter.
        </AppDialog>
      )}
    </div>
  );
}

Object.assign(window, { DataQualityPage });
