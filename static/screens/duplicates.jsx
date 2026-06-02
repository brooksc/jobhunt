// Jobhunt — Duplicates page (list + compare view)

function DuplicatesPage({ mode = "list" }) {
  const groups = window.JH_DUPES;
  const [compareGroup, setCompareGroup] = React.useState(mode === "compare" && groups[0] ? groups[0].id : null);
  const [searchQuery, setSearchQuery] = React.useState("");
  const [keepSelections, setKeepSelections] = React.useState({});

  const jobById = React.useMemo(() => {
    const m = {};
    (window.JH_JOBS || []).forEach(j => { m[j.id] = j; });
    return m;
  }, []);

  function reviewableJob(j) {
    return j && !["archived", "not_available", "duplicate"].includes(j.status);
  }

  const reviewGroups = groups
    .map(g => ({ ...g, jobIds: g.jobIds.filter(id => reviewableJob(jobById[id])) }))
    .filter(g => g.jobIds.length >= 2);

  const filtered = searchQuery
    ? reviewGroups.filter(g => g.jobIds.some(jid => {
        const j = jobById[jid];
        return j && (
          j.company?.toLowerCase().includes(searchQuery.toLowerCase()) ||
          j.title?.toLowerCase().includes(searchQuery.toLowerCase()) ||
          j.sourceUrl?.toLowerCase().includes(searchQuery.toLowerCase())
        );
      }))
    : reviewGroups;

  const cg = reviewGroups.find((g) => g.id === compareGroup);
  if (cg) {
    const jobIds = cg.jobIds;
    const compareAIdx = 0;
    const compareBIdx = 1;
    const left = window.JH_JOBS.find((j) => j.id === jobIds[compareAIdx]);
    const right = window.JH_JOBS.find((j) => j.id === jobIds[compareBIdx]);
    if (!left || !right) return <div className="jh-empty"><strong>Need at least two jobs to compare.</strong></div>;
    return <DuplicateCompare group={cg} left={left} right={right} onBack={() => setCompareGroup(null)} />;
  }

  return (
    <>
      <div className="jh-toolbar">
        <div className="jh-search">
          <Icon.Search size={13} className="ico" />
          <input
            placeholder="Search candidates…"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
          <span className="kbd">⌘K</span>
        </div>
        <div style={{ marginLeft: "auto" }}>
          <span style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>
            {filtered.length} groups · {filtered.reduce((a, g) => a + g.jobIds.length, 0)} candidates
          </span>
        </div>
      </div>

      <div className="jh-tablewrap">
        {filtered.length === 0 && (
          <div style={{ padding: "48px 24px", textAlign: "center", color: "var(--fg-mute)" }}>
            {groups.length === 0
              ? "No duplicate groups found."
              : reviewGroups.length === 0
                ? "No duplicate groups need review."
                : "No groups match your search."}
          </div>
        )}
        {filtered.map((g) => {
          const rows = g.jobIds.map((id) => window.JH_JOBS.find((j) => j.id === id)).filter(Boolean);
          const groupKey = g.cleanedHash || g.id;
          const keepId = keepSelections[groupKey] || g.jobIds[0];
          return (
            <React.Fragment key={g.id}>
              <div className="jh-group">
                <span className="jh-group__title">
                  <Icon.Copy size={11} />
                  <span>{g.reason}</span>
                  <span className="jh-group__hash">· hash {g.hash}</span>
                </span>
                <span style={{ marginLeft: 16, display: "inline-flex", gap: 6, fontSize: 11, color: "var(--fg-mute)" }}>
                  <span data-mono>similarity</span>
                  <span data-mono style={{ color: "var(--fg-strong)" }}>{g.similarity.toFixed(2)}</span>
                </span>
                <div style={{ marginLeft: "auto", display: "flex", gap: 6 }}>
                  <Btn size="sm" icon={<Icon.Split size={11} />} onClick={() => {
                    window.JH_API.decideDuplicate({ cleaned_hash: g.cleanedHash, job_ids: g.jobIds, decision: "not_duplicate" })
                      .then(() => { window.JH_TOAST.show("Marked as not duplicate"); })
                      .catch((e) => window.JH_TOAST.show(e.message, "error"));
                  }}>Not duplicate</Btn>
                  <Btn size="sm" kind="accent" onClick={() => setCompareGroup(g.id)} icon={<Icon.Eye size={11} />}>Compare</Btn>
                  <Btn size="sm" icon={<Icon.Merge size={11} />} onClick={() => {
                    window.JH_API.decideDuplicate({ cleaned_hash: g.cleanedHash, job_ids: g.jobIds, decision: "merged", keep_job_id: keepId })
                      .then(() => { window.JH_TOAST.show("Decision recorded"); })
                      .catch(e => window.JH_TOAST.show(e.message, "error"));
                  }}>Merge</Btn>
                </div>
              </div>
              <table className="jh-table" style={{ tableLayout: "fixed" }}>
                <colgroup>
                  <col style={{ width: 28 }} />
                  <col style={{ width: 100 }} />
                  <col style={{ width: 180 }} />
                  <col style={{ width: 320 }} />
                  <col style={{ width: 110 }} />
                  <col style={{ width: 90 }} />
                  <col style={{ width: 360 }} />
                  <col style={{ width: 120 }} />
                </colgroup>
                <tbody>
                  {rows.map((j) => (
                    <tr key={j.id}>
                      <td>
                        <input type="radio" name={`keep-${groupKey}`}
                          checked={keepId === j.id}
                          onChange={() => setKeepSelections(prev => ({ ...prev, [groupKey]: j.id }))}
                          title="Keep this job"
                        />
                      </td>
                      <td><StatusChip value={j.status} /></td>
                      <td><CompanyCell name={j.company} url={j.sourceUrl} /></td>
                      <td className="col-co">{j.title}</td>
                      <td className="col-mute">{j.remote}</td>
                      <td className="col-mono">{fmtCaptured(j.capturedAt)}</td>
                      <td className="col-mono" style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>
                        <a href={j.sourceUrl} target="_blank" rel="noreferrer" style={{ color: "inherit", textDecoration: "none", display: "inline-flex", gap: 4, alignItems: "center" }}>
                          <Icon.External size={11} />
                          {j.sourceUrl.replace(/^https?:\/\//, "").slice(0, 50)}
                        </a>
                      </td>
                      <td>
                        <span className="row-actions" style={{ visibility: "visible" }}>
                          <Btn size="sm" kind="ghost" icon={<Icon.Pin size={11} />} onClick={() => {
                            window.JH_API.decideDuplicate({ cleaned_hash: g.cleanedHash, job_ids: g.jobIds, decision: "merged", keep_job_id: j.id })
                              .then(() => { window.JH_TOAST.show("Decision recorded"); })
                              .catch(e => window.JH_TOAST.show(e.message, "error"));
                          }}>Keep</Btn>
                          <Btn size="sm" kind="ghost" icon={<Icon.External size={11} />} aria-label="Open source" onClick={() => window.open(j.sourceUrl, "_blank")} />
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </React.Fragment>
          );
        })}
      </div>
    </>
  );
}

function DuplicateCompare({ group, left, right, onBack }) {
  const [compareA, setCompareA] = React.useState(0);
  const [compareB, setCompareB] = React.useState(1);
  const jobIds = group.jobIds;
  const allJobs = jobIds.map(id => window.JH_JOBS.find(j => j.id === id)).filter(Boolean);
  const jobA = allJobs[compareA] || left;
  const jobB = allJobs[compareB] || right;

  function decide(decision, keepJobId) {
    window.JH_API.decideDuplicate({ cleaned_hash: group.cleanedHash, job_ids: group.jobIds, decision, keep_job_id: keepJobId })
      .then(() => { window.JH_TOAST.show("Decision recorded"); })
      .catch(e => window.JH_TOAST.show(e.message, "error"));
  }

  function Side({ j, isA }) {
    const other = isA ? jobB : jobA;
    const diffTitle = j.title !== other.title;
    const diffSal = fmtSalary(j) !== fmtSalary(other);
    return (
      <div className="jh-compare__col">
        <div className="jh-compare__head">
          <CoLogo name={j.company} />
          <div style={{ display: "flex", flexDirection: "column", gap: 1, minWidth: 0 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <strong style={{ fontSize: 13, color: "var(--fg-strong)" }}>{j.company}</strong>
              <StatusChip value={j.status} />
              {allJobs.length > 2 && (
                <select
                  style={{ fontSize: 11, color: "var(--fg-mute)", background: "var(--bg-elev)", border: "1px solid var(--border)", borderRadius: 4, padding: "1px 4px" }}
                  value={isA ? compareA : compareB}
                  onChange={(e) => isA ? setCompareA(Number(e.target.value)) : setCompareB(Number(e.target.value))}
                >
                  {allJobs.map((aj, idx) => (
                    <option key={idx} value={idx}>{aj.company} — {aj.title?.slice(0, 30)}</option>
                  ))}
                </select>
              )}
              {allJobs.length <= 2 && (
                <span style={{ fontSize: 11, color: "var(--fg-faint)", fontFamily: "var(--font-mono)" }}>{isA ? "candidate A · keep" : "candidate B"}</span>
              )}
            </div>
            <span style={{ fontSize: 12, color: "var(--fg-mute)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{j.sourceUrl}</span>
          </div>
          <div style={{ marginLeft: "auto", display: "flex", gap: 4 }}>
            <Btn size="sm" kind="ghost" icon={<Icon.External size={11} />} aria-label="Open source" onClick={() => window.open(j.sourceUrl, "_blank")} />
            {isA ? (
              <Btn size="sm" kind="accent" icon={<Icon.Pin size={11} />} onClick={() => decide("merged", j.id)}>Keep this</Btn>
            ) : (
              <Btn size="sm" icon={<Icon.Trash size={11} />} onClick={() => decide("merged", jobA.id)}>Discard</Btn>
            )}
          </div>
        </div>
        <div className="jh-compare__body">
          <dl className="jh-fields">
            <dt>Title</dt><dd>{diffTitle ? <span className="jh-diff">{j.title}</span> : j.title}</dd>
            <dt>Location</dt><dd>{j.location}</dd>
            <dt>Work mode</dt><dd><span className="jh-tag">{j.workMode}</span></dd>
            <dt>Meets criteria</dt><dd><span className="jh-tag">{j.remote}</span></dd>
            <dt>Salary</dt><dd>{diffSal ? <span className="jh-diff" data-mono>{fmtSalary(j)}</span> : <span data-mono>{fmtSalary(j)}</span>}</dd>
            <dt>Seniority</dt><dd><span className="jh-tag">{j.seniority}</span></dd>
            <dt>Source</dt><dd><span className="jh-tag">{j.source}</span></dd>
            <dt>Captured</dt><dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{fmtDateTime(j.capturedAt)}</dd>
          </dl>
          {j.summary && (
            <div className="jh-section" style={{ marginTop: 12 }}>
              <h3>Summary</h3>
              <p>{j.summary}</p>
            </div>
          )}
          <div className="jh-section">
            <h3>Skills</h3>
            <div className="jh-pills">
              {(j.skills || []).map((s) => <span key={s} className="jh-tag">{s}</span>)}
            </div>
          </div>
          <div className="jh-section">
            <h3>Events</h3>
            <div style={{ fontSize: 12, color: "var(--fg-mute)", display: "flex", flexDirection: "column", gap: 2, fontFamily: "var(--font-mono)" }}>
              {j.events.map((e, i) => <div key={i}>{fmtDateTime(e.at)} · {e.kind}</div>)}
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <>
      <div className="jh-toolbar">
        <Btn size="sm" kind="ghost" icon={<Icon.ChevronLeft size={11} />} onClick={onBack}>Back</Btn>
        <span style={{ fontSize: 12.5, color: "var(--fg-mute)" }}>Compare duplicate group</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11.5, color: "var(--fg-faint)" }}>{group.hash}</span>
        <span style={{ marginLeft: 12, fontSize: 11.5, color: "var(--fg-mute)" }}>
          <span data-mono>similarity </span>
          <span data-mono style={{ color: "var(--fg-strong)" }}>{group.similarity.toFixed(2)}</span>
          <span style={{ margin: "0 8px", color: "var(--fg-faint)" }}>·</span>
          {group.reason}
        </span>
        <div style={{ marginLeft: "auto", display: "flex", gap: 6 }}>
          <Btn size="sm" icon={<Icon.Split size={11} />} onClick={() => decide("not_duplicate", null)}>Not duplicate</Btn>
          <Btn size="sm" kind="accent" icon={<Icon.Merge size={11} />} onClick={() => decide("merged", jobA.id)}>Merge — keep A</Btn>
        </div>
      </div>
      <div className="jh-compare">
        <Side j={jobA} isA={true} />
        <Side j={jobB} isA={false} />
      </div>
      <div style={{ padding: "8px 16px", borderTop: "1px solid var(--border-faint)", fontSize: 11.5, color: "var(--fg-mute)", display: "flex", alignItems: "center", gap: 8 }}>
        <Icon.AlertTriangle size={12} />
        <span>Non-kept jobs are marked duplicate with a reference to the kept job.</span>
      </div>
    </>
  );
}

Object.assign(window, { DuplicatesPage });
