// Jobhunt — Duplicates page (pair validation)

function DuplicatesPage({ mode = "list" }) {
  const [activePairId, setActivePairId] = React.useState(null);
  const [searchQuery, setSearchQuery] = React.useState("");

  const jobById = React.useMemo(() => {
    const m = {};
    (window.JH_JOBS || []).forEach(j => { m[j.id] = j; });
    return m;
  }, [window.JH_JOBS]);

  function reviewableJob(j) {
    return j && !["archived", "not_available", "duplicate"].includes(j.status);
  }

  const pairs = React.useMemo(() => {
    const out = [];
    (window.JH_DUPES || []).forEach((group) => {
      const jobs = group.jobIds.map(id => jobById[id]).filter(reviewableJob);
      if (jobs.length < 2) return;
      const original = jobs[0];
      jobs.slice(1).forEach((candidate, idx) => {
        out.push({
          id: `${group.id}:${original.id}:${candidate.id}`,
          group,
          original,
          candidate,
          index: idx + 1,
          total: jobs.length - 1,
        });
      });
    });
    return out;
  }, [jobById]);

  React.useEffect(() => {
    if (mode === "compare" && !activePairId && pairs[0]) setActivePairId(pairs[0].id);
  }, [mode, activePairId, pairs]);

  const filtered = searchQuery
    ? pairs.filter(({ original, candidate, group }) => {
        const q = searchQuery.toLowerCase();
        return [original, candidate].some(j => (
          j.company?.toLowerCase().includes(q) ||
          j.title?.toLowerCase().includes(q) ||
          j.sourceUrl?.toLowerCase().includes(q)
        )) || group.reason?.toLowerCase().includes(q);
      })
    : pairs;

  const activePair = filtered.find(p => p.id === activePairId) || pairs.find(p => p.id === activePairId);
  if (activePair) {
    return <DuplicatePairValidate pair={activePair} onBack={() => setActivePairId(null)} />;
  }

  return (
    <>
      <div className="jh-toolbar">
        <div className="jh-search">
          <Icon.Search size={13} className="ico" />
          <input
            placeholder="Search duplicate pairs..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
          <span className="kbd">⌘K</span>
        </div>
        <div style={{ marginLeft: "auto" }}>
          <span style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>
            {filtered.length} candidates · {pairs.length} total
          </span>
        </div>
      </div>

      <div className="jh-tablewrap">
        {filtered.length === 0 && (
          <div style={{ padding: "48px 24px", textAlign: "center", color: "var(--fg-mute)" }}>
            {pairs.length === 0 ? "No duplicate pairs need review." : "No pairs match your search."}
          </div>
        )}

        {filtered.length > 0 && (
          <table className="jh-table jh-dupe-pairs" style={{ tableLayout: "fixed" }}>
            <colgroup>
              <col style={{ width: 280 }} />
              <col style={{ width: 280 }} />
              <col style={{ width: 90 }} />
              <col style={{ width: 120 }} />
              <col style={{ width: 280 }} />
              <col style={{ width: 116 }} />
            </colgroup>
            <thead>
              <tr>
                <th>Original</th>
                <th>Possible duplicate</th>
                <th>Similarity</th>
                <th>Captured</th>
                <th>Reason</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((pair) => (
                <DuplicatePairRow key={pair.id} pair={pair} onValidate={() => setActivePairId(pair.id)} />
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}

function DuplicatePairRow({ pair, onValidate }) {
  const { original, candidate, group } = pair;
  return (
    <tr>
      <td><DuplicateJobSummary job={original} label="Original" /></td>
      <td><DuplicateJobSummary job={candidate} label={pair.total > 1 ? `Duplicate ${pair.index} of ${pair.total}` : "Possible duplicate"} /></td>
      <td data-mono>{Number(group.similarity || 0).toFixed(2)}</td>
      <td className="col-mono">{fmtCaptured(candidate.capturedAt)}</td>
      <td className="col-mute">
        <span>{group.reason}</span>
        {group.hash && <span className="jh-group__hash" style={{ display: "block", marginTop: 2 }}>hash {group.hash}</span>}
      </td>
      <td>
        <Btn size="sm" kind="accent" icon={<Icon.Eye size={11} />} onClick={onValidate}>Compare</Btn>
      </td>
    </tr>
  );
}

function DuplicateJobSummary({ job, label }) {
  return (
    <div className="jh-dupe-job">
      <div className="jh-dupe-job__label">{label}</div>
      <div className="jh-dupe-job__main">
        <CompanyCell name={job.company} url={job.sourceUrl} />
        <StatusChip value={job.status} />
      </div>
      <div className="jh-dupe-job__title">{job.title || "Untitled job"}</div>
      <a
        className="jh-dupe-job__url"
        href={job.sourceUrl}
        target="_blank"
        rel="noreferrer"
      >
        <Icon.External size={10} />
        {shortUrl(job.sourceUrl)}
      </a>
    </div>
  );
}

function DuplicatePairValidate({ pair, onBack }) {
  const [busy, setBusy] = React.useState(false);
  const { group, original, candidate } = pair;

  function decide(decision) {
    setBusy(true);
    const payload = {
      job_ids: [original.id, candidate.id],
      decision,
      keep_job_id: decision === "merged" ? original.id : null,
    };
    window.JH_API.decideDuplicate(payload)
      .then(() => {
        window.JH_TOAST.show(decision === "merged" ? "Duplicate confirmed" : "Pair dismissed");
        onBack();
        return window.JH_REFRESH_UI_DATA?.();
      })
      .catch(e => window.JH_TOAST.show(e.message, "error"))
      .finally(() => setBusy(false));
  }

  return (
    <>
      <div className="jh-toolbar">
        <Btn size="sm" kind="ghost" icon={<Icon.ChevronLeft size={11} />} onClick={onBack}>Back</Btn>
        <span style={{ fontSize: 12.5, color: "var(--fg-mute)" }}>Compare duplicate group</span>
        <span style={{ marginLeft: 12, fontSize: 11.5, color: "var(--fg-mute)" }}>
          <span data-mono>similarity </span>
          <span data-mono style={{ color: "var(--fg-strong)" }}>{Number(group.similarity || 0).toFixed(2)}</span>
          <span style={{ margin: "0 8px", color: "var(--fg-faint)" }}>·</span>
          {group.reason}
        </span>
        <div style={{ marginLeft: "auto", display: "flex", gap: 6 }}>
          <Btn size="sm" icon={<Icon.Split size={11} />} disabled={busy} onClick={() => decide("not_duplicate")}>Dismiss Pair</Btn>
          <Btn size="sm" kind="accent" icon={<Icon.Check size={11} />} disabled={busy} onClick={() => decide("merged")}>Confirm Duplicate</Btn>
        </div>
      </div>
      <div className="jh-compare">
        <DuplicateCompareSide job={original} role="Original" other={candidate} />
        <DuplicateCompareSide job={candidate} role="Possible duplicate" other={original} />
      </div>
      <div className="jh-dupe-footer">
        <Icon.AlertTriangle size={12} />
        <span>Confirm Duplicate keeps the original record and marks the right-hand job as duplicate.</span>
      </div>
    </>
  );
}

function DuplicateCompareSide({ job, role, other }) {
  const diffTitle = normalizeCompare(job.title) !== normalizeCompare(other.title);
  const diffCompany = normalizeCompare(job.company) !== normalizeCompare(other.company);
  const diffLocation = normalizeCompare(job.location) !== normalizeCompare(other.location);
  const diffWorkMode = normalizeCompare(job.workMode) !== normalizeCompare(other.workMode);
  const diffSalary = normalizeCompare(fmtSalary(job)) !== normalizeCompare(fmtSalary(other));

  return (
    <div className="jh-compare__col">
      <div className="jh-compare__head">
        <CoLogo name={job.company} />
        <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0 }}>
          <span className="jh-dupe-role">{role}</span>
          <div style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 0 }}>
            <strong style={{ fontSize: 13, color: "var(--fg-strong)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{job.company || "Unknown company"}</strong>
            <StatusChip value={job.status} />
          </div>
          <a className="jh-dupe-source" href={job.sourceUrl} target="_blank" rel="noreferrer">{shortUrl(job.sourceUrl)}</a>
        </div>
        <div style={{ marginLeft: "auto" }}>
          <Btn size="sm" kind="ghost" icon={<Icon.External size={11} />} aria-label="Open source" onClick={() => window.open(job.sourceUrl, "_blank")} />
        </div>
      </div>
      <div className="jh-compare__body">
        <dl className="jh-fields">
          <dt>Company</dt><dd>{diffCompany ? <span className="jh-diff">{job.company || "—"}</span> : (job.company || "—")}</dd>
          <dt>Title</dt><dd>{diffTitle ? <span className="jh-diff">{job.title || "—"}</span> : (job.title || "—")}</dd>
          <dt>Location</dt><dd>{diffLocation ? <span className="jh-diff">{job.location || "—"}</span> : (job.location || "—")}</dd>
          <dt>Work mode</dt><dd>{diffWorkMode ? <span className="jh-diff">{job.workMode || "—"}</span> : (job.workMode || "—")}</dd>
          <dt>Meets criteria</dt><dd><span className="jh-tag">{job.remote}</span></dd>
          <dt>Salary</dt><dd>{diffSalary ? <span className="jh-diff" data-mono>{fmtSalary(job)}</span> : <span data-mono>{fmtSalary(job)}</span>}</dd>
          <dt>Seniority</dt><dd><span className="jh-tag">{job.seniority || "—"}</span></dd>
          <dt>Captured</dt><dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{fmtDateTime(job.capturedAt)}</dd>
        </dl>
        {job.summary && (
          <div className="jh-section" style={{ marginTop: 12 }}>
            <h3>Summary</h3>
            <p>{job.summary}</p>
          </div>
        )}
        <div className="jh-section">
          <h3>Skills</h3>
          <div className="jh-pills">
            {(job.skills || []).length
              ? job.skills.map((s) => <span key={s} className="jh-tag">{s}</span>)
              : <span style={{ color: "var(--fg-faint)", fontSize: 12 }}>No skills extracted</span>}
          </div>
        </div>
        <div className="jh-section">
          <h3>Source text</h3>
          <p className="jh-dupe-description">{job.cleanedDescription || "No captured description available."}</p>
        </div>
      </div>
    </div>
  );
}

function shortUrl(url) {
  return String(url || "").replace(/^https?:\/\//, "").slice(0, 64) || "No source URL";
}

function normalizeCompare(value) {
  return String(value || "").trim().toLowerCase();
}

Object.assign(window, { DuplicatesPage });
