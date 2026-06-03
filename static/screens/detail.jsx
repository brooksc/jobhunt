// Jobhunt — Job detail panel (tabs, inline edit, timeline, raw)

function EditableField({ value, onSave, children }) {
  const [editing, setEditing] = React.useState(false);
  const [draft, setDraft] = React.useState(value || "");
  const ref = React.useRef(null);

  React.useEffect(() => { if (editing) ref.current?.focus(); }, [editing]);

  const commit = () => {
    const trimmed = draft.trim();
    if (trimmed !== (value || "")) onSave(trimmed);
    setEditing(false);
  };

  if (editing) {
    return (
      <input
        ref={ref}
        className="jh-input"
        style={{ fontSize: "inherit", padding: "2px 6px" }}
        value={draft}
        onChange={e => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={e => {
          if (e.key === "Enter") commit();
          if (e.key === "Escape") setEditing(false);
        }}
      />
    );
  }
  return (
    <span
      className="editable"
      style={{ cursor: "text" }}
      onClick={() => { setDraft(value || ""); setEditing(true); }}
      title="Click to edit"
    >
      {children || value || "—"}
    </span>
  );
}

function JobDetail({ jobId, onClose, initialTab = "overview", jobIds = [], onNavigate }) {
  const job = window.JH_JOBS.find((j) => j.id === jobId);
  const [tab, setTab] = React.useState(initialTab);
  const [note, setNote] = React.useState("");
  const [noteDialog, setNoteDialog] = React.useState(false);
  const [localOverrides, setLocalOverrides] = React.useState({});

  const currentIndex = jobIds.indexOf(jobId);
  const prevId = currentIndex > 0 ? jobIds[currentIndex - 1] : null;
  const nextId = currentIndex < jobIds.length - 1 ? jobIds[currentIndex + 1] : null;

  React.useEffect(() => {
    const handler = (e) => {
      if (document.activeElement && ["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) return;
      if (e.key === "ArrowLeft" && prevId) onNavigate && onNavigate(prevId);
      if (e.key === "ArrowRight" && nextId) onNavigate && onNavigate(nextId);
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [prevId, nextId]);

  if (!job) {
    return (
      <div className="jh-panel">
        <div className="jh-empty"><strong>No job selected</strong><span>Click a row to view details.</span></div>
      </div>
    );
  }

  // Merge local overrides on top of job data
  const effectiveJob = { ...job, ...localOverrides };

  function patchJob(field, value, label) {
    window.JH_API.api(`/api/jobs/${job.id}`, { method: "PATCH", body: JSON.stringify({ [field]: value }) })
      .then(() => {
        window.JH_TOAST.show(`${label} updated`);
        setLocalOverrides(prev => ({ ...prev, [field]: value }));
      })
      .catch(e => window.JH_TOAST.show(e.message, "error"));
  }

  return (
    <div className="jh-panel">
      <div className="jh-panel__head">
        <div className="jh-panel__hrow">
          <span className="jh-panel__co">
            <span className="logo">{(window.JH_COMPANIES[job.company] || {}).mono || "??"}</span>
            <span>{job.company}</span>
            <span style={{ color: "var(--fg-faint)" }}>·</span>
            <span className="jh-tag" style={{ height: 16, fontSize: 10.5 }}>{job.source}</span>
          </span>
          <div style={{ marginLeft: "auto", display: "flex", gap: 4 }}>
            <Btn kind="ghost" size="sm" icon={<Icon.ChevronLeft size={11} />} title="Previous job" aria-label="Previous job"
              disabled={!prevId}
              onClick={() => prevId && onNavigate && onNavigate(prevId)} />
            <Btn kind="ghost" size="sm" icon={<Icon.ChevronRight size={11} />} title="Next job" aria-label="Next job"
              disabled={!nextId}
              onClick={() => nextId && onNavigate && onNavigate(nextId)} />
            <Btn kind="ghost" size="sm" icon={<Icon.X size={11} />} onClick={onClose} title="Close" aria-label="Close detail panel" />
          </div>
        </div>

        <div className="jh-panel__title">
          <span className="jh-tag" style={{ height: 18, fontSize: 11, verticalAlign: "middle", marginRight: 8 }}>#{job.jobNumber}</span>
          {job.title}
        </div>

        <div className="jh-panel__sub">
          <span>{job.location}</span>
          <span className="sep">·</span>
          <span>{job.remote}</span>
          <span className="sep">·</span>
          <span data-mono>{fmtSalary(job)}</span>
          <span className="sep">·</span>
          <span>{job.employment}</span>
          <span className="sep">·</span>
          <span>{job.seniority || "—"}</span>
        </div>

        <div className="jh-panel__actions">
          <StatusDropdown value={job.status} onChange={(status) => window.JH_API.setStatus(job.id, status).catch((e) => window.JH_TOAST.show(e.message, "error"))} />
          <Btn size="sm" icon={<Icon.External size={11} />} onClick={() => window.JH_API.openJobSource(job.id, job.sourceUrl)}>Open source</Btn>
          <Btn size="sm" icon={<Icon.Refresh size={11} />} onClick={() => window.JH_API.rerunExtraction(job.id).catch((e) => window.JH_TOAST.show(e.message, "error"))}>Re-run</Btn>
          <Btn size="sm" icon={<Icon.Note size={11} />} onClick={() => setNoteDialog(true)}>Add note</Btn>
          <Btn size="sm" kind="ghost" icon={<Icon.Archive size={11} />} title="Archive" aria-label="Archive job" onClick={() => window.JH_API.archiveJob(job.id).catch((e) => window.JH_TOAST.show(e.message, "error"))} />
          <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 6 }}>
            <ExtractionChip ext={job.extraction} />
          </div>
        </div>
        {noteDialog && (
          <AppTextInputDialog
            title="Add note"
            placeholder="Add a note…"
            multiline={true}
            onConfirm={(noteText) => {
              setNoteDialog(false);
              window.JH_API.api(`/api/jobs/${job.id}/notes`, { method: "POST", body: JSON.stringify({ note: noteText }) })
                .then(() => { window.JH_TOAST.show("Note added"); window.JH_REFRESH_UI_DATA(); })
                .catch(e => window.JH_TOAST.show(e.message, "error"));
            }}
            onClose={() => setNoteDialog(false)}
          />
        )}
      </div>

      <div className="jh-tabs" role="tablist" onKeyDown={(e) => {
        const tabs = ["overview", "timeline", "description", "raw"];
        const current = tabs.indexOf(tab);
        if (e.key === "ArrowRight" && current < tabs.length - 1) { e.preventDefault(); setTab(tabs[current + 1]); }
        if (e.key === "ArrowLeft" && current > 0) { e.preventDefault(); setTab(tabs[current - 1]); }
      }}>
        {["overview", "timeline", "description", "raw"].map((t) => (
          <button
            key={t}
            role="tab"
            aria-selected={tab === t}
            tabIndex={tab === t ? 0 : -1}
            className="jh-tab"
            onClick={() => setTab(t)}
          >
            {t.charAt(0).toUpperCase() + t.slice(1)}
            {t === "timeline" && job.events.length > 0 && <span className="jh-tab__badge">{job.events.length}</span>}
          </button>
        ))}
      </div>

      <div className="jh-panel__body">
        {tab === "overview" && <OverviewTab job={effectiveJob} onPatch={patchJob} onClose={onClose} />}
        {tab === "timeline" && <TimelineTab job={job} note={note} setNote={setNote} />}
        {tab === "description" && <DescriptionTab job={job} />}
        {tab === "raw" && <RawTab job={job} />}
      </div>
    </div>
  );
}

function StatusDropdown({ value, onChange }) {
  const [open, setOpen] = React.useState(false);
  const ref = React.useRef(null);
  React.useEffect(() => {
    function h(e) { if (ref.current && !ref.current.contains(e.target)) setOpen(false); }
    document.addEventListener("mousedown", h);
    return () => document.removeEventListener("mousedown", h);
  }, []);
  return (
    <div ref={ref} style={{ position: "relative" }}>
      <button className="jh-btn jh-btn--sm" onClick={() => setOpen((v) => !v)} style={{ paddingRight: 6 }}>
        <StatusChip value={value} />
        <Icon.ChevronDown size={10} />
      </button>
      {open && (
        <div style={{
          position: "absolute", top: 28, left: 0, zIndex: 50,
          background: "var(--bg-elev-2)", border: "1px solid var(--border-strong)",
          borderRadius: "var(--r-2)", boxShadow: "var(--shadow-popover)",
          minWidth: 160, padding: 4,
        }}>
          {window.JH_STATUSES.map((s) => (
            <button key={s} style={{
              display: "flex", alignItems: "center", gap: 8, width: "100%",
              padding: "6px 8px", borderRadius: 4, fontSize: 12.5,
              background: s === value ? "var(--bg-hover)" : "transparent",
              textAlign: "left", cursor: "pointer",
            }} onClick={() => { setOpen(false); if (s !== value) onChange(s); }}>
              {s === value ? <Icon.Check size={11} /> : <span style={{ width: 11 }}></span>}
              <StatusChip value={s} />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function OverviewTab({ job, onPatch, onClose }) {
  const [localSkills, setLocalSkills] = React.useState(job.skills || []);
  const [skillsDirty, setSkillsDirty] = React.useState(false);
  const [addSkillDialog, setAddSkillDialog] = React.useState(false);

  function saveSkills(skills) {
    window.JH_API.api(`/api/jobs/${job.id}/skills`, { method: "PATCH", body: JSON.stringify({ skills }) })
      .then(() => { window.JH_TOAST.show("Skills updated"); setSkillsDirty(false); })
      .catch(e => window.JH_TOAST.show(e.message, "error"));
  }

  function removeSkill(skill) {
    const updated = localSkills.filter(s => s !== skill);
    setLocalSkills(updated);
    setSkillsDirty(true);
  }

  return (
    <>
      {addSkillDialog && (
        <AppTextInputDialog
          title="Add skill"
          placeholder="e.g. Python, React, SQL"
          onConfirm={(skill) => {
            setAddSkillDialog(false);
            const updated = [...localSkills, skill.trim()];
            setLocalSkills(updated);
            setSkillsDirty(true);
          }}
          onClose={() => setAddSkillDialog(false)}
        />
      )}
      <div style={{ marginBottom: 8 }}>
        <StarRating
          value={job.rating}
          onChange={(r) => {
            window.JH_API.setRating(job.id, r)
              .catch(e => window.JH_TOAST.show(e.message, "error"));
          }}
          size={16}
        />
      </div>
      <dl className="jh-fields">
        <dt>Job ID</dt><dd><span className="jh-tag">#{job.jobNumber}</span></dd>
        <dt>Company</dt>
        <dd>
          <EditableField value={job.company} onSave={(v) => onPatch("company", v, "Company")}>
            {job.company}
          </EditableField>
        </dd>
        <dt>Title</dt>
        <dd>
          <EditableField value={job.title} onSave={(v) => onPatch("title", v, "Title")}>
            {job.title}
          </EditableField>
        </dd>
        <dt>Location</dt>
        <dd>
          <EditableField value={job.location} onSave={(v) => onPatch("location", v, "Location")}>
            {job.location}
          </EditableField>
          <FieldProvenance job={job} field="location" />
        </dd>
        <dt>Work mode</dt><dd><span className="jh-tag">{job.workMode}</span><FieldProvenance job={job} field="workMode" /></dd>
        <dt>Meets criteria</dt><dd><span className="jh-tag">{job.remote}</span><FieldProvenance job={job} field="meetsCriteria" /></dd>
        <dt>Salary</dt>
        <dd style={{ flexDirection: "column", alignItems: "flex-start", gap: 2 }}>
          <span>
            <span className="editable" data-mono>{fmtSalary(job)}</span>
            {(job.salaryMin || job.salaryMax) && job.currency && <span style={{ color: "var(--fg-faint)", fontSize: 11, marginLeft: 4 }}>· {job.currency}</span>}
            <FieldProvenance job={job} field="salary" />
          </span>
          {job.salaryNote && <span style={{ color: "var(--fg-mute)", fontSize: 11.5, lineHeight: 1.4 }}>{job.salaryNote}</span>}
        </dd>
        <dt>Employment</dt><dd><span className="jh-tag">{job.employment}</span></dd>
        <dt>Seniority</dt><dd>{job.seniority ? <span className="jh-tag">{job.seniority}</span> : <span style={{ color: "var(--fg-faint)" }}>—</span>}</dd>
        <dt>Skills</dt>
        <dd>
          <div className="jh-pills">
            {localSkills.map((s) => (
              <span key={s} className="jh-tag" style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
                {s}
                <button
                  style={{ background: "none", border: "none", cursor: "pointer", padding: 0, color: "var(--fg-faint)", lineHeight: 1 }}
                  onClick={() => removeSkill(s)}
                  title="Remove skill"
                >
                  <Icon.X size={10} />
                </button>
              </span>
            ))}
            <button className="jh-tag" style={{ borderStyle: "dashed", color: "var(--fg-faint)", background: "transparent" }}
              onClick={() => setAddSkillDialog(true)}>+ add</button>
          </div>
          {skillsDirty && (
            <div style={{ marginTop: 6 }}>
              <Btn size="sm" kind="accent" onClick={() => saveSkills(localSkills)}>Save skills</Btn>
              <Btn size="sm" kind="ghost" style={{ marginLeft: 4 }} onClick={() => { setLocalSkills(job.skills || []); setSkillsDirty(false); }}>Discard</Btn>
            </div>
          )}
        </dd>
        <dt>Source</dt>
        <dd>
          <span className="jh-tag">{job.source}</span>
          <a href={job.sourceUrl} target="_blank" rel="noreferrer" onClick={(e) => { e.preventDefault(); window.JH_API.openJobSource(job.id, job.sourceUrl); }} style={{ color: "var(--fg-mute)", textDecoration: "none", display: "inline-flex", alignItems: "center", gap: 4, fontSize: 11.5, fontFamily: "var(--font-mono)" }}>
            <Icon.External size={11} />
            <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: 220 }}>{job.sourceUrl.replace(/^https?:\/\//, "")}</span>
          </a>
        </dd>
        {job.applicationUrl && job.applicationUrl !== job.sourceUrl && (
          <>
            <dt>Apply link</dt>
            <dd>
              <a href={job.applicationUrl} target="_blank" rel="noreferrer" style={{ color: "var(--accent)", textDecoration: "none", display: "inline-flex", alignItems: "center", gap: 4, fontSize: 11.5, fontFamily: "var(--font-mono)" }}>
                <Icon.External size={11} />
                <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: 220 }}>{job.applicationUrl.replace(/^https?:\/\//, "")}</span>
              </a>
            </dd>
          </>
        )}
      </dl>

      {job.summary && (
        <div className="jh-section">
          <h3>Summary</h3>
          <p>{job.summary}</p>
        </div>
      )}

      {(job.requirements || []).length > 0 && (
        <div className="jh-section">
          <h3>Requirements</h3>
          <ul>{job.requirements.map((r, i) => <li key={i}>{r}</li>)}</ul>
        </div>
      )}

      {(job.niceToHaves || []).length > 0 && (
        <div className="jh-section">
          <h3>Nice to have</h3>
          <ul>{job.niceToHaves.map((r, i) => <li key={i}>{r}</li>)}</ul>
        </div>
      )}

      {(job.benefits || []).length > 0 && (
        <div className="jh-section">
          <h3>Benefits</h3>
          <div className="jh-pills" style={{ marginTop: 2 }}>
            {job.benefits.map((b) => <span key={b} className="jh-tag">{b}</span>)}
          </div>
        </div>
      )}

      <FitScorePanel job={job} />
      <CaptureDiagnostics job={job} onClose={onClose} />

      <div className="jh-section">
        <h3>Extraction</h3>
        <dl className="jh-fields" style={{ gridTemplateColumns: "110px 1fr" }}>
          <dt>Status</dt><dd><ExtractionChip ext={job.extraction} /></dd>
          <dt>Extracted at</dt><dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{fmtDateTime(job.extraction.at)}</dd>
          {job.extraction.model && <><dt>Model</dt><dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{job.extraction.model}</dd></>}
          {job.extraction.error && (
            <>
              <dt>Error</dt>
              <dd style={{ flexDirection: "column", alignItems: "flex-start", gap: 6 }}>
                <span style={{ color: "var(--st-rejected)", fontSize: 12, fontFamily: "var(--font-mono)" }}>{job.extraction.error}</span>
                <Btn size="sm" kind="accent" icon={<Icon.Refresh size={11} />}
                  onClick={() => {
                    window.JH_API.api(`/api/jobs/${job.id}/extract`, { method: "POST" })
                      .then(() => { window.JH_TOAST.show("Queued for re-extraction"); window.JH_REFRESH_UI_DATA(); })
                      .catch(e => window.JH_TOAST.show(e.message, "error"));
                  }}>
                  Retry extraction
                </Btn>
              </dd>
            </>
          )}
        </dl>
      </div>
    </>
  );
}

function FieldProvenance({ job, field }) {
  const source = job.fieldProvenance?.[field] || "unknown";
  const confidenceKey = field === "workMode" ? "remote_type" : field === "salary" ? "salary" : field === "meetsCriteria" ? "meets_criteria" : field;
  const confidence = job.extraction?.fieldConfidence?.[confidenceKey];
  const confidenceText = confidence != null ? ` · ${Math.round(Number(confidence) * 100)}%` : "";
  const color = source === "not set" ? "var(--fg-faint)" : source === "manual override" ? "var(--st-offer)" : "var(--fg-mute)";
  return (
    <span
      className="jh-tag"
      title={`Source: ${source}${confidenceText}`}
      style={{ marginLeft: 6, color, borderColor: "var(--border)", fontSize: 10.5 }}
    >
      {source}{confidenceText}
    </span>
  );
}

function TimelineTab({ job, note, setNote }) {
  const [actionDialog, setActionDialog] = React.useState(null); // null | "note" | "date"
  const [pendingActionNote, setPendingActionNote] = React.useState("");
  const [statusDialog, setStatusDialog] = React.useState(false);

  function handleSaveNote() {
    if (!note.trim()) return;
    window.JH_API.addNote(job.id, note)
      .then(() => { window.JH_TOAST.show("Note added"); window.JH_REFRESH_UI_DATA(); })
      .catch((e) => window.JH_TOAST.show(e.message, "error"));
  }

  return (
    <>
      {actionDialog === "note" && (
        <AppTextInputDialog
          title="Set next action"
          placeholder="e.g. Follow up with recruiter"
          onConfirm={(n) => { setPendingActionNote(n); setActionDialog("date"); }}
          onClose={() => setActionDialog(null)}
        />
      )}
      {actionDialog === "date" && (
        <AppTextInputDialog
          title="Due date"
          placeholder={`Days from now (default: ${window.JH_SETTINGS.followup_default_days || 7})`}
          defaultValue={String(window.JH_SETTINGS.followup_default_days || 7)}
          onConfirm={(daysStr) => {
            const days = parseInt(daysStr) || (window.JH_SETTINGS.followup_default_days || 7);
            const due = new Date();
            due.setDate(due.getDate() + days);
            const dueDateStr = due.toISOString().slice(0, 10);
            setActionDialog(null);
            window.JH_API.createAction(job.id, pendingActionNote, dueDateStr)
              .catch((e) => window.JH_TOAST.show(e.message, "error"));
          }}
          onClose={() => setActionDialog("note")}
        />
      )}
      {statusDialog && (
        <AppSelectDialog
          title="Change status"
          options={window.JH_STATUSES.map(s => ({ value: s, label: s.charAt(0).toUpperCase() + s.slice(1) }))}
          onConfirm={(status) => {
            setStatusDialog(false);
            window.JH_API.api(`/api/jobs/${job.id}/status`, { method: "PATCH", body: JSON.stringify({ status }) })
              .then(() => { window.JH_TOAST.show(`Status updated to ${status}`); window.JH_REFRESH_UI_DATA(); })
              .catch(e => window.JH_TOAST.show(e.message, "error"));
          }}
          onClose={() => setStatusDialog(false)}
        />
      )}

      <div className="jh-note">
        <span className="jh-note__avatar">B</span>
        <div style={{ flex: 1 }}>
          <textarea
            placeholder="Add a note — keyboard shortcut ⌘↵ to save"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            onKeyDown={(e) => {
              if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
                e.preventDefault();
                handleSaveNote();
              }
            }}
          />
          <div className="jh-note__footer">
            <Btn size="sm" kind="ghost" icon={<Icon.Calendar size={11} />} onClick={() => setActionDialog("note")}>Set next action</Btn>
            <Btn size="sm" kind="ghost" icon={<Icon.Tag size={11} />} onClick={() => setStatusDialog(true)}>Status</Btn>
            <span style={{ marginLeft: "auto", display: "flex", gap: 6 }}>
              <Kbd>⌘↵</Kbd>
              <Btn size="sm" kind="accent" onClick={handleSaveNote}>Save note</Btn>
            </span>
          </div>
        </div>
      </div>

      {job.nextAction && (
        <div style={{ margin: "0 0 12px", padding: "10px 14px", background: "var(--bg-elev)", border: "1px solid var(--border)", borderRadius: "var(--r-2)", display: "flex", alignItems: "center", gap: 10 }}>
          <span className="jh-due" data-state={dueState(job.nextAction.dueDate)}>
            <Icon.Clock size={11} />
            <span>{dueLabel(job.nextAction.dueDate)}</span>
          </span>
          <span style={{ flex: 1, fontSize: 12.5, color: "var(--fg)" }}>{job.nextAction.note}</span>
          <Btn size="sm" kind="ghost" icon={<Icon.Check size={11} />}
            onClick={() => window.JH_API.completeAction(job.nextAction.id)
              .then(() => window.JH_TOAST.show("Action completed"))
              .catch((e) => window.JH_TOAST.show(e.message, "error"))}>
            Complete
          </Btn>
        </div>
      )}

      <div className="jh-tl">
        {[...job.events].reverse().map((e, i) => <TimelineItem key={i} ev={e} />)}
      </div>
    </>
  );
}

function TimelineItem({ ev }) {
  const I = {
    capture: <Icon.Inbox size={10} />,
    recapture: <Icon.Refresh size={10} />,
    applied: <Icon.ArrowRight size={10} />,
    status: <Icon.Tag size={10} />,
    note: <Icon.Note size={10} />,
    interview: <Icon.Calendar size={10} />,
    offer: <Icon.Sparkles size={10} />,
    rejected: <Icon.X size={10} />,
  }[ev.kind] || <Icon.Clock size={10} />;
  const TITLES = {
    capture: "Captured",
    recapture: "Recaptured",
    source_opened: "Source opened",
    applied: "Applied",
    status: "Status changed",
    note: "Note added",
    interview: "Interview",
    offer: "Offer received",
    rejected: "Rejected",
  };
  return (
    <div className="jh-tl__item">
      <div className="jh-tl__dot" data-kind={ev.kind}>{I}</div>
      <div className="jh-tl__body">
        <div className="jh-tl__title">{TITLES[ev.kind] || ev.kind}</div>
        <div className="jh-tl__meta">{fmtDateTime(ev.at)}</div>
        {(ev.note || ev.body) && <div className="jh-tl__note">{ev.note || ev.body}</div>}
      </div>
    </div>
  );
}

function DescriptionTab({ job }) {
  const body = job.cleanedDescription || job.summary || "";
  return (
    <div className="jh-section" style={{ marginTop: 0 }}>
      <h3>Cleaned description</h3>
      <div style={{ fontSize: 13, lineHeight: 1.6, color: "var(--fg)" }}>
        <p style={{ marginTop: 0 }}>
          <strong style={{ color: "var(--fg-strong)" }}>{job.title}</strong> · {job.company}
        </p>
        {body ? <pre className="jh-raw" style={{ whiteSpace: "pre-wrap" }}>{body}</pre> : <p>No cleaned description available.</p>}
        {(job.requirements || []).length > 0 && (
          <>
            <h4 style={{ fontSize: 12, color: "var(--fg-strong)", margin: "16px 0 6px" }}>What you'll do</h4>
            <ul style={{ paddingLeft: 18, margin: 0, color: "var(--fg)" }}>
              {job.requirements.map((r, i) => <li key={i} style={{ marginBottom: 4 }}>{r}</li>)}
            </ul>
          </>
        )}
        {(job.niceToHaves || []).length > 0 && (
          <>
            <h4 style={{ fontSize: 12, color: "var(--fg-strong)", margin: "16px 0 6px" }}>Bonus</h4>
            <ul style={{ paddingLeft: 18, margin: 0, color: "var(--fg)" }}>
              {job.niceToHaves.map((r, i) => <li key={i} style={{ marginBottom: 4 }}>{r}</li>)}
            </ul>
          </>
        )}
      </div>
    </div>
  );
}

function RawTab({ job }) {
  const bytes = (n) => `${Number(n || 0).toLocaleString()} bytes`;
  return (
    <>
      <dl className="jh-fields" style={{ marginBottom: 16 }}>
        <dt>Capture URL</dt>
        <dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{job.sourceUrl}</dd>
        <dt>Canonical URL</dt>
        <dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{job.canonicalUrl || "—"}</dd>
        <dt>Captured at</dt>
        <dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{fmtDateTime(job.capturedAt)}</dd>
        <dt>Content hash</dt>
        <dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{job.rawHash ? `sha256:${job.rawHash}` : "—"}</dd>
        <dt>Cleaned hash</dt>
        <dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{job.cleanedHash ? `sha256:${job.cleanedHash}` : "—"}</dd>
        <dt>Byte size</dt>
        <dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{bytes(job.rawByteSize)}</dd>
        <dt>Visible size</dt>
        <dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{bytes(job.visibleByteSize)}</dd>
        <dt>Cleaned size</dt>
        <dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{bytes(job.cleanedByteSize)}</dd>
        <dt>Selected text</dt>
        <dd>{job.selectedTextPresent ? <span className="jh-tag">present</span> : <span style={{ color: "var(--fg-faint)" }}>—</span>}</dd>
        <dt>Structured data</dt>
        <dd>{job.structuredDataCount > 0 ? <span className="jh-tag">{job.structuredDataCount} item{job.structuredDataCount !== 1 ? "s" : ""}</span> : <span style={{ color: "var(--fg-faint)" }}>—</span>}</dd>
        {job.extraction.model && (
          <>
            <dt>Model</dt>
            <dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{job.extraction.model}</dd>
          </>
        )}
        {job.extraction.confidence != null && (
          <>
            <dt>Confidence</dt>
            <dd data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{(job.extraction.confidence * 100).toFixed(0)}%</dd>
          </>
        )}
      </dl>
      <div className="jh-section" style={{ marginTop: 0 }}>
        <h3>Raw captured text</h3>
        <pre className="jh-raw">{job.raw}</pre>
      </div>
    </>
  );
}

function CaptureDiagnostics({ job, onClose }) {
  const [deleteConfirm, setDeleteConfirm] = React.useState(false);
  const deleteTimer = React.useRef(null);

  function armDelete() {
    setDeleteConfirm(true);
    deleteTimer.current = setTimeout(() => setDeleteConfirm(false), 3000);
  }
  function cancelDelete() {
    clearTimeout(deleteTimer.current);
    setDeleteConfirm(false);
  }
  function confirmDelete() {
    clearTimeout(deleteTimer.current);
    setDeleteConfirm(false);
    window.JH_API.deleteJob(job.id)
      .then(() => { window.JH_TOAST?.show("Job deleted"); return window.JH_REFRESH_UI_DATA?.(); })
      .then(() => onClose?.())
      .catch((e) => window.JH_TOAST?.show(e.message, "error"));
  }

  React.useEffect(() => () => clearTimeout(deleteTimer.current), []);

  const bytes = (n) => `${Number(n || 0).toLocaleString()} bytes`;
  const likelyTruncated = (job.rawByteSize || 0) < 1000 || (job.cleanedByteSize || 0) < 700;
  const copyDebugSummary = async () => {
    const summary = [
      `Job #${job.jobNumber}: ${job.title || "(untitled)"}`,
      `Company: ${job.company || "—"}`,
      `Status: ${job.status || "—"}`,
      `Source URL: ${job.sourceUrl || "—"}`,
      `Canonical URL: ${job.canonicalUrl || "—"}`,
      `Captured: ${fmtDateTime(job.capturedAt)}`,
      `Processed: ${fmtDateTime(job.extraction?.at)}`,
      `Raw bytes: ${job.rawByteSize || 0}`,
      `Visible bytes: ${job.visibleByteSize || 0}`,
      `Cleaned bytes: ${job.cleanedByteSize || 0}`,
      `Selected text: ${job.selectedTextPresent ? "present" : "missing"}`,
      `Structured data: ${job.structuredDataCount || 0}`,
      `Likely truncated: ${likelyTruncated ? "yes" : "no"}`,
      `Extraction status: ${job.extraction?.status || "—"}`,
      `Extraction model: ${job.extraction?.model || "—"}`,
      `Extraction error: ${job.extraction?.error || "—"}`,
    ].join("\n");
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(summary);
      } else {
        const ta = document.createElement("textarea");
        ta.value = summary;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        document.execCommand("copy");
        ta.remove();
      }
      window.JH_TOAST?.show("Debug summary copied");
    } catch (e) {
      window.JH_TOAST?.show(e.message || "Copy failed", "error");
    }
  };
  const rows = [
    ["Raw text", bytes(job.rawByteSize)],
    ["Visible text", bytes(job.visibleByteSize)],
    ["Cleaned text", bytes(job.cleanedByteSize)],
    ["Selected text", job.selectedTextPresent ? "present" : "—"],
    ["Structured data", job.structuredDataCount > 0 ? `${job.structuredDataCount} item${job.structuredDataCount !== 1 ? "s" : ""}` : "—"],
    ["Captured", fmtCaptured(job.capturedAt)],
    ["Processed", fmtCaptured(job.extraction?.at)],
    ["Canonical", job.canonicalUrl ? job.canonicalUrl.replace(/^https?:\/\//, "") : "—"],
  ];
  return (
    <div className="jh-section">
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8, flexWrap: "wrap" }}>
        <h3 style={{ margin: 0 }}>Capture diagnostics</h3>
        <div style={{ marginLeft: "auto", display: "flex", gap: 4, flexWrap: "wrap" }}>
          <Btn size="sm" kind="ghost" icon={<Icon.External size={11} />} onClick={() => window.JH_API.openJobSource(job.id, job.sourceUrl)}>Open source</Btn>
          <Btn size="sm" kind="ghost" icon={<Icon.Refresh size={11} />} onClick={() => {
            window.JH_API.rerunExtraction(job.id)
              .then(() => { window.JH_TOAST?.show("Queued for re-extraction"); return window.JH_REFRESH_UI_DATA?.(); })
              .catch((e) => window.JH_TOAST?.show(e.message, "error"));
          }}>Re-run AI</Btn>
          <Btn size="sm" kind="ghost" icon={<Icon.X size={11} />} onClick={() => {
            window.JH_API.setStatus(job.id, "not_available")
              .then(() => { window.JH_TOAST?.show("Marked unavailable"); return window.JH_REFRESH_UI_DATA?.(); })
              .catch((e) => window.JH_TOAST?.show(e.message, "error"));
          }}>Mark unavailable</Btn>
          <Btn size="sm" kind="ghost" icon={<Icon.Archive size={11} />} onClick={() => {
            window.JH_API.archiveJob(job.id)
              .then(() => { window.JH_TOAST?.show("Job archived"); return window.JH_REFRESH_UI_DATA?.(); })
              .catch((e) => window.JH_TOAST?.show(e.message, "error"));
          }}>Archive</Btn>
          {deleteConfirm
            ? <><Btn size="sm" kind="danger" icon={<Icon.Trash size={11} />} onClick={confirmDelete}>Confirm delete</Btn>
                <Btn size="sm" kind="ghost" onClick={cancelDelete}>Cancel</Btn></>
            : <Btn size="sm" kind="ghost" icon={<Icon.Trash size={11} />} onClick={armDelete}>Delete</Btn>
          }
          <Btn size="sm" kind="ghost" icon={<Icon.Copy size={11} />} onClick={copyDebugSummary}>Copy debug</Btn>
        </div>
      </div>
      {likelyTruncated && (
        <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 8, color: "var(--st-screening)", fontSize: 12 }}>
          <Icon.AlertTriangle size={12} />
          <span>Likely truncated capture; recapture this job if important fields are missing.</span>
        </div>
      )}
      <dl className="jh-fields" style={{ gridTemplateColumns: "110px 1fr" }}>
        {rows.map(([label, value]) => (
          <React.Fragment key={label}>
            <dt>{label}</dt>
            <dd data-mono style={{
              fontSize: 11.5,
              color: value === "—" ? "var(--fg-faint)" : "var(--fg-mute)",
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            }}>
              {value}
            </dd>
          </React.Fragment>
        ))}
        <dt>Extraction</dt>
        <dd>
          <ExtractionChip ext={job.extraction} />
          {job.extraction?.model && <span data-mono style={{ fontSize: 11.5, color: "var(--fg-mute)" }}>{job.extraction.model}</span>}
        </dd>
      </dl>
    </div>
  );
}

const FIT_DIMENSION_LABELS = {
  required_qualifications: "Required quals",
  preferred_qualifications: "Preferred quals",
  skills: "Skills",
  experience_level: "Experience",
  domain_fit: "Domain fit",
};

function fitColor(score) {
  if (score == null) return "var(--fg-faint)";
  if (score >= 75) return "var(--st-offer)";
  if (score >= 50) return "var(--st-screening)";
  return "var(--st-rejected)";
}

function FitScorePanel({ job }) {
  const fit = job.fit || {};
  const status = fit.status || "none";
  const [busy, setBusy] = React.useState(false);
  const hasStoredFitScore = fit.score != null;

  const hasResume = !!String(window.JH_SETTINGS?.resume_text || "").trim();
  const extracted = job.extraction?.status === "ok";

  function trigger() {
    setBusy(true);
    window.JH_API.scoreFit(job.id)
      .then(() => window.JH_TOAST.show("Fit scoring queued"))
      .catch((e) => window.JH_TOAST.show(e.message, "error"))
      .finally(() => setBusy(false));
  }

  const scoreBtn = (label) => (
    <Btn
      size="sm"
      kind="accent"
      icon={<Icon.Sparkles size={11} />}
      disabled={busy || !hasResume || !extracted}
      title={!hasResume ? "Add your resume in Settings first" : !extracted ? "Extract this job first" : undefined}
      onClick={trigger}
    >
      {busy ? "Queuing…" : label}
    </Btn>
  );

  return (
    <div className="jh-section">
      <h3>Resume fit</h3>
      {!hasResume && (
        <p style={{ color: "var(--fg-mute)", fontSize: 12.5 }}>
          Add your resume in Settings to score how well you fit this job.
        </p>
      )}
      {hasResume && status === "none" && (
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <span style={{ color: "var(--fg-mute)", fontSize: 12.5 }}>
            {extracted ? "Not scored yet." : "Extract this job first, then score fit."}
          </span>
          {scoreBtn("Score fit")}
        </div>
      )}
      {hasResume && status === "pending" && !hasStoredFitScore && (
        <p style={{ color: "var(--fg-mute)", fontSize: 12.5, display: "inline-flex", alignItems: "center", gap: 6 }}>
          <Icon.Clock size={12} /> Scoring queued — check the LLM Queue.
        </p>
      )}
      {hasResume && status === "failed" && (
        <div style={{ display: "flex", flexDirection: "column", gap: 8, alignItems: "flex-start" }}>
          <span style={{ color: "var(--st-rejected)", fontSize: 12, fontFamily: "var(--font-mono)" }}>
            {fit.error || "Fit scoring failed."}
          </span>
          {scoreBtn("Retry scoring")}
        </div>
      )}
      {(status === "succeeded" || (status === "pending" && hasStoredFitScore)) && (
        <>
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 10 }}>
            <span style={{ fontSize: 28, fontWeight: 700, color: fitColor(fit.score), fontVariantNumeric: "tabular-nums", lineHeight: 1 }}>
              {fit.score}
            </span>
            <span style={{ color: "var(--fg-faint)", fontSize: 12 }}>/ 100 overall fit</span>
            <span style={{ marginLeft: "auto" }}>{status === "pending" ? (
              <span style={{ color: "var(--fg-mute)", fontSize: 12, display: "inline-flex", alignItems: "center", gap: 6 }}>
                <Icon.Clock size={12} /> Re-scoring queued
              </span>
            ) : scoreBtn("Re-score")}</span>
          </div>
          {fit.summary && (
            <p style={{ fontSize: 12.5, color: "var(--fg)", marginTop: 0, lineHeight: 1.5 }}>{fit.summary}</p>
          )}
          {((fit.requirements_met || []).length > 0 || (fit.requirements_not_met || []).length > 0) && (
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginTop: 10, marginBottom: 10 }}>
              {(fit.requirements_met || []).length > 0 && (
                <div>
                  <div style={{ fontSize: 12, color: "var(--fg-strong)", fontWeight: 600, marginBottom: 4 }}>Requirements met</div>
                  <ul style={{ margin: 0, paddingLeft: 18, color: "var(--fg-mute)", fontSize: 11.5, lineHeight: 1.45 }}>
                    {fit.requirements_met.map((item, i) => <li key={i}>{item}</li>)}
                  </ul>
                </div>
              )}
              {(fit.requirements_not_met || []).length > 0 && (
                <div>
                  <div style={{ fontSize: 12, color: "var(--fg-strong)", fontWeight: 600, marginBottom: 4 }}>Requirements not met</div>
                  <ul style={{ margin: 0, paddingLeft: 18, color: "var(--fg-mute)", fontSize: 11.5, lineHeight: 1.45 }}>
                    {fit.requirements_not_met.map((item, i) => <li key={i}>{item}</li>)}
                  </ul>
                </div>
              )}
            </div>
          )}
          <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 8 }}>
            {(fit.dimensions || []).map((d) => (
              <div key={d.name}>
                <div style={{ display: "flex", alignItems: "baseline", gap: 8, fontSize: 12 }}>
                  <span style={{ color: "var(--fg-strong)", minWidth: 120 }}>{FIT_DIMENSION_LABELS[d.name] || d.name}</span>
                  <span style={{ color: fitColor(d.score), fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>{d.score}</span>
                </div>
                <div style={{ height: 5, borderRadius: 3, background: "var(--bg-elev-2)", overflow: "hidden", margin: "3px 0" }}>
                  <div style={{ width: `${Math.max(0, Math.min(100, d.score))}%`, height: "100%", background: fitColor(d.score) }}></div>
                </div>
                {d.rationale && <div style={{ fontSize: 11.5, color: "var(--fg-mute)", lineHeight: 1.4 }}>{d.rationale}</div>}
              </div>
            ))}
          </div>
          {fit.model && (
            <div style={{ marginTop: 8, fontSize: 11, color: "var(--fg-faint)", fontFamily: "var(--font-mono)" }}>
              {fit.model}{fit.scoredAt ? ` · ${fmtDateTime(fit.scoredAt)}` : ""}
            </div>
          )}
        </>
      )}
    </div>
  );
}

Object.assign(window, { JobDetail });
