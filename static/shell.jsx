// Jobhunt — App shell (sidebar + topbar)

const SAVED_VIEWS_KEY = "jobhunt.saved_views";
function loadSavedViews() { try { return JSON.parse(localStorage.getItem(SAVED_VIEWS_KEY) || "[]"); } catch { return []; } }
function persistSavedViews(views) {
  localStorage.setItem(SAVED_VIEWS_KEY, JSON.stringify(views));
  window.dispatchEvent(new CustomEvent("jobhunt:views-changed"));
}

const SAVED_VIEW_SET_VALUE = "(set)";
const SAVED_VIEW_NOT_SET_VALUE = "(not set)";

function savedViewDisplayValue(value) {
  const text = String(value ?? "").trim();
  return text && text !== "—" && text.toLowerCase() !== "unknown" ? text : "";
}

function savedViewDynamicField(job, key) {
  if (key === "workMode") return { value: job.workMode, set: savedViewDisplayValue(job.workMode) !== "" };
  if (key === "employment") return { value: job.employment, set: savedViewDisplayValue(job.employment) !== "" };
  if (key === "seniority") return { value: job.seniority, set: savedViewDisplayValue(job.seniority) !== "" };
  if (key === "source") return { value: job.source, set: savedViewDisplayValue(job.source) !== "" };
  if (key === "company") return { value: job.company, set: savedViewDisplayValue(job.company) !== "" };
  if (key === "location") return { value: job.location, set: savedViewDisplayValue(job.location) !== "" };
  if (key === "salary") return { value: fmtSalary(job), set: Boolean(job.salaryMin || job.salaryMax || job.salaryNote) };
  if (key === "fit") return { value: job.fit?.score != null ? String(job.fit.score) : "", set: job.fit?.score != null };
  if (key === "nextAction") return { value: job.nextAction ? "Has follow-up" : "", set: Boolean(job.nextAction) };
  return { value: "", set: false };
}

function savedViewDynamicFilterMatches(job, key, wanted) {
  if (!wanted || wanted === "All") return true;
  const field = savedViewDynamicField(job, key);
  if (wanted === SAVED_VIEW_SET_VALUE) return field.set;
  if (wanted === SAVED_VIEW_NOT_SET_VALUE) return !field.set;
  return savedViewDisplayValue(field.value) === wanted;
}

function savedViewMatchesJob(job, view) {
  const filters = view.filters || {};
  const q = (view.q || "").toLowerCase().trim();
  if (q) {
    const matchNum = q.startsWith("#") ? q.slice(1) : q;
    const textMatch = `${job.company} ${job.title} ${job.location}`.toLowerCase().includes(q);
    const numMatch = String(job.jobNumber) === matchNum || String(job.jobNumber).includes(matchNum);
    if (!textMatch && !numMatch) return false;
  }
  if (Array.isArray(filters.status)) {
    if (!filters.status.includes(job.status)) return false;
  } else if (filters.status && filters.status !== "All" && job.status !== filters.status.toLowerCase().replace(/ /g, "_")) return false;
  if (filters.remote && filters.remote !== "All" && job.remote !== filters.remote) return false;
  if (filters.extraction && filters.extraction !== "All") {
    const extMap = { OK: "ok", Pending: "pending", Failed: "fail" };
    if (job.extraction.status !== (extMap[filters.extraction] ?? filters.extraction)) return false;
  }
  if (filters.source && filters.source !== "All" && job.source !== filters.source) return false;
  if (filters.dup === "Has candidate" && !job.hasDuplicate) return false;
  if (filters.dup === "No candidate" && job.hasDuplicate) return false;
  if (filters.minRating && filters.minRating !== "All") {
    const minR = parseInt(filters.minRating.replace(/[^\d]/g, ""), 10);
    if ((job.rating || 0) < minR) return false;
  }
  if (filters.salary && filters.salary !== "All") {
    if (filters.salary === SAVED_VIEW_SET_VALUE && !(job.salaryMax || job.salaryMin || job.salaryNote)) return false;
    if (filters.salary === SAVED_VIEW_NOT_SET_VALUE && (job.salaryMax || job.salaryMin || job.salaryNote)) return false;
    if (filters.salary === SAVED_VIEW_SET_VALUE || filters.salary === SAVED_VIEW_NOT_SET_VALUE) return true;
    const minSalary = parseInt(filters.salary.replace(/[^\d]/g, ""), 10) * 1000;
    if ((job.salaryMax || job.salaryMin || 0) < minSalary) return false;
  }
  if (filters.recentDays && daysFrom(job.capturedAt.slice(0, 10)) < -filters.recentDays) return false;
  for (const [key, value] of Object.entries(filters.dynamic || {})) {
    if (!savedViewDynamicFilterMatches(job, key, value)) return false;
  }
  return true;
}

function applySavedView(name, setRoute, setSavedViewName) {
  window.JH_PENDING_SAVED_VIEW = name;
  setSavedViewName?.(name);
  setRoute("jobs");
  setTimeout(() => {
    if (window.JH_APPLY_SAVED_VIEW) {
      window.JH_APPLY_SAVED_VIEW(name);
      delete window.JH_PENDING_SAVED_VIEW;
    }
  }, 30);
}

function Sidebar({ route, setRoute, setSavedViewName, theme, themeMode, onToggleTheme }) {
  const metrics = window.JH_METRICS || {};
  const queueStats = window.JH_QUEUE_STATS || {};
  const queueCount = Number.isFinite(queueStats.totalOutstanding)
    ? queueStats.totalOutstanding
    : (metrics.pendingExtraction || 0) + (metrics.failedExtraction || 0);
  const [customViews, setCustomViews] = React.useState(() => loadSavedViews());

  React.useEffect(() => {
    function handler() { setCustomViews(loadSavedViews()); }
    window.addEventListener("jobhunt:views-changed", handler);
    return () => window.removeEventListener("jobhunt:views-changed", handler);
  }, []);

  function deleteView(name, e) {
    e.stopPropagation();
    persistSavedViews(loadSavedViews().filter(v => v.name !== name));
  }

  // Extension status — based on last captured job
  const lastCapture = (window.JH_JOBS || []).reduce((latest, j) =>
    !latest || j.capturedAt > latest ? j.capturedAt : latest, null);
  const extensionAge = lastCapture ? daysFrom(lastCapture.slice(0, 10)) : null;
  const extensionLabel = lastCapture
    ? `Extension · ${extensionAge === 0 ? "used today" : `${Math.abs(extensionAge)}d ago`}`
    : "Extension · no captures yet";
  const extensionState = extensionAge !== null && extensionAge > -7 ? "ok" : "warn";

  // LM Studio status — based on settings
  const llmConfigured = !!(window.JH_SETTINGS?.llm_base_url);
  const llmLabel = llmConfigured
    ? `LM Studio · ${window.JH_SETTINGS.llm_model || "configured"}`
    : "LM Studio · not configured";
  const llmState = llmConfigured ? "ok" : "warn";
  const qualityIssueCount = (window.JH_JOBS || []).filter((j) => {
    if (j.status === "archived" || j.status === "not_available" || j.status === "duplicate") return false;
    return qualityIssuesForJob(j).length > 0;
  }).length;
  const queuePaused = window.JH_SETTINGS?.llm_queue_paused === 'true';
  const nav = [
    { id: "dashboard", label: "Dashboard", icon: "Home" },
    { id: "jobs", label: "Jobs", icon: "Briefcase", count: metrics.jobs || window.JH_JOBS.length },
    { id: "quality", label: "Data Quality", icon: "AlertTriangle", count: qualityIssueCount || undefined },
    { id: "needs", label: "Needs Action", icon: "Bell", count: metrics.needsAction || 0 },
    { id: "llm-queue", label: "LLM Queue", icon: "Inbox", count: queueCount || undefined, warn: queuePaused },
    { id: "sites", label: "Sites", icon: "Globe", count: metrics.sites || window.JH_SITES.length },
    { id: "duplicates", label: "Duplicates", icon: "Copy", count: metrics.duplicateGroups || window.JH_DUPES.length },
  ];
  return (
    <aside className="jh-side">
      <div className="jh-side__tl-space" />
      <div className="jh-side__brand">
        <span className="jh-side__mark">J</span>
        <span>Jobhunt</span>
        <span style={{ marginLeft: "auto", color: "var(--fg-faint)", fontSize: 11, fontFamily: "var(--font-mono)" }}>{window.JH_SETTINGS.version || ""}</span>
      </div>

      <div className="jh-side__user">
        <span className="avatar">B</span>
        <span>brooks · local</span>
      </div>

      <div className="jh-side__group">
        {nav.map((n) => {
          const Ico = Icon[n.icon];
          return (
            <button
              key={n.id}
              className="jh-side__nav"
              aria-current={route === n.id ? "page" : undefined}
              onClick={() => {
                if (n.id === "jobs") setSavedViewName?.(null);
                setRoute(n.id);
              }}
            >
              <Ico />
              <span>{n.label}</span>
              {n.warn && <span className="jh-side__warn" title="Queue paused">⏸</span>}
              {n.count != null && <span className="jh-side__count">{n.count}</span>}
            </button>
          );
        })}
      </div>

      <div className="jh-side__sep"></div>

      <div className="jh-side__group">
        <div className="jh-side__label">Saved views</div>
        <button className="jh-side__nav" onClick={() => {
          applySavedView("active", setRoute, setSavedViewName);
        }}>
          <Icon.Pin />
          <span>Active applications</span>
          <span className="jh-side__count">{(metrics.applied || 0) + (metrics.interview || 0) + (metrics.offers || 0)}</span>
        </button>
        <button className="jh-side__nav" onClick={() => {
          applySavedView("remote", setRoute, setSavedViewName);
        }}>
          <Icon.Pin />
          <span>Meets criteria</span>
          <span className="jh-side__count">{window.JH_JOBS.filter((j) => j.remote === "Yes").length}</span>
        </button>
        <button className="jh-side__nav" onClick={() => {
          applySavedView("recent", setRoute, setSavedViewName);
        }}>
          <Icon.Pin />
          <span>This week's captures</span>
          <span className="jh-side__count">{window.JH_JOBS.filter((j) => daysFrom(j.capturedAt.slice(0, 10)) >= -7).length}</span>
        </button>
        {customViews.map(v => (
          <button key={v.name} className="jh-side__nav" onClick={() => {
            applySavedView(v.name, setRoute, setSavedViewName);
          }}>
            <Icon.Pin />
            <span style={{ flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{v.name}</span>
            <span className="jh-side__count">{window.JH_JOBS.filter((j) => savedViewMatchesJob(j, v)).length}</span>
            <span
              onClick={(e) => deleteView(v.name, e)}
              title="Delete view"
              style={{ marginLeft: 4, opacity: 0.5, display: "inline-flex", alignItems: "center", padding: "0 2px" }}
            ><Icon.X size={10} /></span>
          </button>
        ))}
        <button className="jh-side__nav" style={{ color: "var(--fg-faint)" }} onClick={() => {
          setSavedViewName?.(null);
          setRoute("jobs");
          setTimeout(() => window.JH_OPEN_SAVE_VIEW_DIALOG?.(), 30);
        }}>
          <Icon.Plus />
          <span>Save current view…</span>
        </button>
      </div>

      <div className="jh-side__sep"></div>

      <button
        className="jh-side__nav"
        aria-current={route === "settings" ? "page" : undefined}
        onClick={() => setRoute("settings")}
      >
        <Icon.Settings />
        <span>Settings</span>
      </button>
      <button
        className="jh-side__nav"
        aria-current={route === "help" ? "page" : undefined}
        onClick={() => setRoute("help")}
      >
        <Icon.Help />
        <span>Help</span>
      </button>

      <div className="jh-side__footer">
        <div className="jh-side__status">
          <span className="dot dot--ok"></span>
          <span>Local service · ok</span>
        </div>
        <div className="jh-side__status">
          <span className={`dot dot--${extensionState}`}></span>
          <span>{extensionLabel}</span>
        </div>
        <div className="jh-side__status">
          <span className={`dot dot--${llmState}`}></span>
          <span>{llmLabel}</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 6 }}>
          <button
            className="jh-btn jh-btn--ghost jh-btn--sm"
            style={{ padding: "0 6px", height: 22 }}
            onClick={onToggleTheme}
            title="Toggle theme"
          >
            {theme === "dark" ? <Icon.Sun size={12} /> : <Icon.Moon size={12} />}
            <span style={{ fontSize: 11 }}>{themeMode === "auto" ? "Auto" : theme === "dark" ? "Light" : "Auto"}</span>
          </button>
          <span style={{ marginLeft: "auto", fontSize: 10.5, color: "var(--fg-faint)", fontFamily: "var(--font-mono)" }}>{window.JH_SETTINGS.db_path || "local db"}</span>
        </div>
      </div>
    </aside>
  );
}

const ROUTE_LABELS = {
  dashboard: "Dashboard",
  jobs: "Jobs",
  quality: "Data Quality",
  needs: "Needs Action",
  sites: "Sites",
  duplicates: "Duplicates",
  "llm-queue": "LLM Queue",
  settings: "Settings",
  help: "Help",
};

function TopBar({ route, children, right }) {
  return (
    <div className="jh-topbar">
      <div className="jh-topbar__crumbs">
        <span>Workspace</span>
        <span className="sep">/</span>
        <strong>{ROUTE_LABELS[route]}</strong>
        {children}
      </div>
      <div className="jh-topbar__sp"></div>
      <div className="jh-topbar__act">
        {right}
      </div>
    </div>
  );
}

Object.assign(window, { Sidebar, TopBar, ROUTE_LABELS });
