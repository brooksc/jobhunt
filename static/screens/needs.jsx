// Jobhunt — Needs Action page

const DUE_FILTERS = ["all", "overdue", "today", "upcoming"];
const DUE_LABELS = { all: "All", overdue: "Overdue", today: "Today", upcoming: "Upcoming" };

function NeedsActionPage({ onSelectJob }) {
  const [search, setSearch] = React.useState("");
  const [dueFilter, setDueFilter] = React.useState("all");
  const [statusFilter, setStatusFilter] = React.useState("all");
  const [statusDropdownOpen, setStatusDropdownOpen] = React.useState(false);
  const statusDropdownRef = React.useRef(null);
  const statusDropdownButtonRef = React.useRef(null);
  const [snoozeDialog, setSnoozeDialog] = React.useState(null);
  const [actionDialog, setActionDialog] = React.useState(null);
  const [pendingActionNote, setPendingActionNote] = React.useState("");

  React.useEffect(() => {
    function h(e) { if (statusDropdownRef.current && !statusDropdownRef.current.contains(e.target)) setStatusDropdownOpen(false); }
    document.addEventListener("mousedown", h);
    return () => document.removeEventListener("mousedown", h);
  }, []);
  React.useEffect(() => {
    function h(e) {
      if (e.key !== "Escape" || !statusDropdownOpen) return;
      setStatusDropdownOpen(false);
      statusDropdownButtonRef.current?.focus();
    }
    document.addEventListener("keydown", h);
    return () => document.removeEventListener("keydown", h);
  }, [statusDropdownOpen]);

  const today = new Date().toISOString().slice(0, 10);

  const allJobs = window.JH_JOBS.filter((j) => j.nextAction !== null);

  const filtered = allJobs.filter((j) => {
    if (statusFilter !== "all" && j.status !== statusFilter) return false;
    if (search.trim()) {
      const q = search.toLowerCase();
      if (
        !(j.company || "").toLowerCase().includes(q) &&
        !(j.title || "").toLowerCase().includes(q) &&
        !(j.nextAction.note || "").toLowerCase().includes(q)
      ) return false;
    }
    return true;
  });

  const items = filtered.map((j) => ({
    job: j,
    due: j.nextAction.dueDate,
    state: dueState(j.nextAction.dueDate),
    days: daysFrom(j.nextAction.dueDate),
  })).sort((a, b) => a.days - b.days);

  const overdue = items.filter((i) => i.state === "overdue");
  const todayItems = items.filter((i) => i.state === "today");
  const soon = items.filter((i) => i.state === "soon" || i.state === "future");

  const visibleSections = {
    overdue: dueFilter === "all" || dueFilter === "overdue",
    today: dueFilter === "all" || dueFilter === "today",
    upcoming: dueFilter === "all" || dueFilter === "upcoming",
  };

  const hasAny = (visibleSections.overdue && overdue.length > 0) ||
    (visibleSections.today && todayItems.length > 0) ||
    (visibleSections.upcoming && soon.length > 0);

  function cycleDueFilter() {
    const next = DUE_FILTERS[(DUE_FILTERS.indexOf(dueFilter) + 1) % DUE_FILTERS.length];
    setDueFilter(next);
  }

  function snoozeAllOverdue() {
    const days = window.JH_SETTINGS?.followup_default_days || 7;
    Promise.all(overdue.map(({ job }) =>
      window.JH_API.snoozeAction(job.nextAction.id, days)
    ))
      .then(() => window.JH_TOAST.show(`Snoozed ${overdue.length} overdue action(s)`))
      .catch((e) => window.JH_TOAST.show(e.message, "error"));
  }

  function Section({ title, hint, rows }) {
    if (!rows.length) return null;
    const color = title === "Overdue" ? "var(--st-rejected)" : title === "Today" ? "var(--st-screening)" : "var(--fg-mute)";
    return (
      <>
        <tr className="jh-group-row">
          <td colSpan={7} style={{
            height: 30, padding: "0 16px",
            background: "var(--bg)", borderBottom: "1px solid var(--border-faint)",
            borderTop: "1px solid var(--border-faint)",
          }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <span style={{ fontSize: 11.5, color: "var(--fg-mute)", fontWeight: 500, display: "inline-flex", alignItems: "center", gap: 6 }}>
                <span style={{ color }}>●</span>
                {title}
              </span>
              {hint && <span style={{ fontSize: 11, color: "var(--fg-faint)" }}>{hint}</span>}
              <span style={{ marginLeft: "auto", fontSize: 11, color: "var(--fg-faint)", fontFamily: "var(--font-mono)" }}>{rows.length}</span>
            </div>
          </td>
        </tr>
        {rows.map(({ job }) => (
          <NeedsRow
            key={job.id}
            job={job}
            onSelectJob={onSelectJob}
            onSnooze={(action) => setSnoozeDialog(action)}
          />
        ))}
      </>
    );
  }

  return (
    <>
      {snoozeDialog && (
        <AppTextInputDialog
          title="Snooze action"
          placeholder="Days to snooze (default: 7)"
          defaultValue={String(window.JH_SETTINGS?.followup_default_days || 7)}
          onConfirm={(val) => {
            const days = parseInt(val) || (window.JH_SETTINGS?.followup_default_days || 7);
            setSnoozeDialog(null);
            window.JH_API.snoozeAction(snoozeDialog.id, days)
              .then(() => window.JH_TOAST.show("Action snoozed"))
              .catch((e) => window.JH_TOAST.show(e.message, "error"));
          }}
          onClose={() => setSnoozeDialog(null)}
        />
      )}
      {actionDialog && actionDialog._step === "note" && (
        <AppTextInputDialog
          title="Set next action"
          placeholder="e.g. Follow up with recruiter"
          onConfirm={(note) => {
            setPendingActionNote(note);
            setActionDialog({ ...actionDialog, _step: "date" });
          }}
          onClose={() => setActionDialog(null)}
        />
      )}
      {actionDialog && actionDialog._step === "date" && (
        <AppTextInputDialog
          title="Due date"
          placeholder={`Days from now (default: ${window.JH_SETTINGS?.followup_default_days || 7})`}
          defaultValue={String(window.JH_SETTINGS?.followup_default_days || 7)}
          onConfirm={(daysStr) => {
            const days = parseInt(daysStr) || (window.JH_SETTINGS?.followup_default_days || 7);
            const due = new Date();
            due.setDate(due.getDate() + days);
            const dueDateStr = due.toISOString().slice(0, 10);
            const jobId = actionDialog.id;
            setActionDialog(null);
            window.JH_API.createAction(jobId, pendingActionNote, dueDateStr)
              .then(() => window.JH_TOAST.show("Action set"))
              .catch((e) => window.JH_TOAST.show(e.message, "error"));
          }}
          onClose={() => setActionDialog({ ...actionDialog, _step: "note" })}
        />
      )}

      <div className="jh-toolbar">
        <div className="jh-search">
          <Icon.Search size={13} className="ico" />
          <input
            placeholder="Search follow-ups…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          {search && <span className="kbd" style={{ cursor: "pointer" }} onClick={() => setSearch("")}>✕</span>}
        </div>

        <button className="jh-filter" data-active={dueFilter !== "all" ? "true" : undefined} onClick={cycleDueFilter}>
          <span className="label">Due</span>
          <span className="val">{DUE_LABELS[dueFilter]}</span>
          <Icon.ChevronDown size={10} />
        </button>

        <div ref={statusDropdownRef} style={{ position: "relative" }}>
          <button
            ref={statusDropdownButtonRef}
            className="jh-filter"
            data-active={statusFilter !== "all" ? "true" : undefined}
            aria-haspopup="menu"
            aria-expanded={statusDropdownOpen}
            onClick={() => setStatusDropdownOpen((v) => !v)}
          >
            <span className="label">Status</span>
            <span className="val">{statusFilter === "all" ? "All" : statusFilter.charAt(0).toUpperCase() + statusFilter.slice(1)}</span>
            <Icon.ChevronDown size={10} />
          </button>
          {statusDropdownOpen && (
            <div style={{
              position: "absolute", top: 32, left: 0, zIndex: 50,
              background: "var(--bg-elev-2)", border: "1px solid var(--border-strong)",
              borderRadius: "var(--r-2)", boxShadow: "var(--shadow-popover)",
              minWidth: 140, padding: 4,
            }}>
              {["all", ...(window.JH_STATUSES || [])].map((s) => (
                <button key={s} style={{
                  display: "flex", alignItems: "center", gap: 8, width: "100%",
                  padding: "6px 8px", borderRadius: 4, fontSize: 12.5,
                  background: s === statusFilter ? "var(--bg-hover)" : "transparent",
                  textAlign: "left", cursor: "pointer",
                }} onClick={() => { setStatusFilter(s); setStatusDropdownOpen(false); }}>
                  {s === statusFilter ? <Icon.Check size={11} /> : <span style={{ width: 11 }} />}
                  {s === "all" ? "All statuses" : <StatusChip value={s} />}
                </button>
              ))}
            </div>
          )}
        </div>

        <div style={{ marginLeft: "auto", display: "flex", gap: 6 }}>
          {overdue.length > 0 && (
            <Btn kind="ghost" size="sm" icon={<Icon.Snooze size={12} />} onClick={snoozeAllOverdue}>
              Snooze all overdue
            </Btn>
          )}
        </div>
      </div>

      {allJobs.length === 0 ? (
        <div className="jh-empty" style={{ margin: 32 }}>
          <Icon.Check size={20} />
          <strong>No follow-ups yet</strong>
          <span>Open a job and use "Set next action" to schedule a check-in.</span>
        </div>
      ) : !hasAny ? (
        <div className="jh-empty" style={{ margin: 32 }}>
          <Icon.Filter size={20} />
          <strong>No results</strong>
          <span>No follow-ups match the current filters.</span>
        </div>
      ) : (
        <div className="jh-tablewrap">
          <table className="jh-table" style={{ tableLayout: "fixed" }}>
            <colgroup>
              <col style={{ width: 130 }} />
              <col style={{ width: 100 }} />
              <col style={{ width: 160 }} />
              <col style={{ width: 240 }} />
              <col style={{ width: 220 }} />
              <col style={{ width: 360 }} />
              <col style={{ width: 180 }} />
            </colgroup>
            <thead>
              <tr>
                <th>Due</th>
                <th>Status</th>
                <th>Company</th>
                <th>Title</th>
                <th>Last event</th>
                <th>Next action</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {visibleSections.overdue && <Section title="Overdue" hint="resolve these first" rows={overdue} />}
              {visibleSections.today && <Section title="Today" hint={new Date().toLocaleDateString()} rows={todayItems} />}
              {visibleSections.upcoming && <Section title="Upcoming" hint="next 7 days" rows={soon} />}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

function NeedsRow({ job, onSelectJob, onSnooze }) {
  const last = job.events[job.events.length - 1];
  const [noteDialog, setNoteDialog] = React.useState(false);
  return (
    <>
      {noteDialog && (
        <AppTextInputDialog
          title="Add note"
          placeholder="Add a note…"
          multiline={true}
          onConfirm={(note) => {
            setNoteDialog(false);
            window.JH_API.addNote(job.id, note)
              .then(() => window.JH_TOAST.show("Note added"))
              .catch((e) => window.JH_TOAST.show(e.message, "error"));
          }}
          onClose={() => setNoteDialog(false)}
        />
      )}
      <tr
        tabIndex={0}
        role="row"
        onClick={() => onSelectJob(job.id)}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onSelectJob(job.id); } }}
      >
        <td className="col-shrink">
          <span className="jh-due" data-state={dueState(job.nextAction.dueDate)}>
            <Icon.Clock size={11} />
            <span>{dueLabel(job.nextAction.dueDate)}</span>
          </span>
        </td>
        <td><StatusChip value={job.status} /></td>
        <td><CompanyCell name={job.company} url={job.sourceUrl} /></td>
        <td className="col-co" title={job.title}>{job.title}</td>
        <td className="col-mute">
          {last ? (
            <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <Icon.Clock size={10} /> {fmtDate(last.at)} · {last.kind}
            </span>
          ) : "—"}
        </td>
        <td title={job.nextAction.note}>{job.nextAction.note}</td>
        <td onClick={(e) => e.stopPropagation()}>
          <span className="row-actions">
            <Btn size="sm" kind="ghost" icon={<Icon.Check size={11} />} title="Mark followed up" aria-label="Mark followed up"
              onClick={() => window.JH_API.completeAction(job.nextAction.id)
                .then(() => window.JH_TOAST.show("Marked as followed up"))
                .catch((e) => window.JH_TOAST.show(e.message, "error"))} />
            <Btn size="sm" kind="ghost" icon={<Icon.Note size={11} />} title="Add note" aria-label="Add note"
              onClick={(e) => { e.stopPropagation(); setNoteDialog(true); }} />
            <Btn size="sm" kind="ghost" icon={<Icon.Snooze size={11} />} title="Snooze" aria-label="Snooze action"
              onClick={(e) => { e.stopPropagation(); onSnooze(job.nextAction); }} />
          </span>
        </td>
      </tr>
    </>
  );
}

Object.assign(window, { NeedsActionPage });
