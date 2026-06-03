// Jobhunt — Jobs page (dense table) + filters + batch actions

const SAVED_VIEWS_KEY = "jobhunt.saved_views";
function loadSavedViews() { try { return JSON.parse(localStorage.getItem(SAVED_VIEWS_KEY) || "[]"); } catch { return []; } }
function persistSavedViews(views) {
  localStorage.setItem(SAVED_VIEWS_KEY, JSON.stringify(views));
  window.dispatchEvent(new CustomEvent("jobhunt:views-changed"));
}

const DEFAULT_COLUMNS = ["company", "title", "status", "rating", "fit", "salaryMin", "salaryMax", "lastOpened"];
const ALL_COLUMNS = ["company", "title", "status", "rating", "fit", "salaryMin", "salaryMax", "remote", "location", "source", "seniority", "employment", "captured", "lastOpened", "processed", "extraction"];
const COLUMN_LABELS = {
  company: "Company", title: "Title", status: "Status", rating: "Rating", fit: "Fit", salaryMin: "Salary min", salaryMax: "Salary max",
  remote: "Meets criteria", location: "Location", source: "Source", seniority: "Seniority",
  employment: "Employment", captured: "Last captured", lastOpened: "Last opened", processed: "Last processed", extraction: "Extraction",
};

const SORT_OPTIONS = [
  { key: "capturedAt", label: "Last captured" },
  { key: "lastOpenedAt", label: "Last opened" },
  { key: "lastProcessedAt", label: "Last processed" },
  { key: "company", label: "Company" },
  { key: "title", label: "Job title" },
  { key: "status", label: "Status" },
  { key: "rating", label: "Rating" },
  { key: "fitScore", label: "Fit score" },
  { key: "salaryMin", label: "Salary (min)" },
  { key: "salaryMax", label: "Salary (max)" },
  { key: "remote", label: "Meets criteria" },
  { key: "location", label: "Location" },
  { key: "seniority", label: "Seniority" },
  { key: "employment", label: "Employment" },
  { key: "source", label: "Source" },
  { key: "extractionStatus", label: "Extraction" },
  { key: "nextActionDue", label: "Next action" },
];

const SET_VALUE = "(set)";
const NOT_SET_VALUE = "(not set)";
const FIXED_FILTER_DEFS = [
  { key: "status", label: "Status", options: () => ["All", "Saved", "Applied", "Interview", "Offer", "Rejected", "Archived", "Not available", "Duplicate"], reset: "All" },
  { key: "remote", label: "Meets criteria", options: () => ["All", "Yes", "No"], reset: "All" },
  { key: "minRating", label: "Rating", options: () => ["All", "★3+", "★4+", "★5"], reset: "All" },
  { key: "extraction", label: "Extraction", options: () => ["All", "OK", "Pending", "Failed"], reset: "All" },
  { key: "source", label: "Source", options: ({ sourceOptions }) => ["All", ...sourceOptions], reset: "All" },
  { key: "dup", label: "Duplicates", options: () => ["All", "Has candidate", "No candidate"], reset: "All" },
  { key: "salary", label: "Salary", options: () => ["All", SET_VALUE, NOT_SET_VALUE, "$150k+", "$200k+", "$250k+"], reset: "All" },
];
const DYNAMIC_FILTER_DEFS = [
  { key: "workMode", label: "Work mode", get: (j) => j.workMode },
  { key: "employment", label: "Employment", get: (j) => j.employment },
  { key: "seniority", label: "Seniority", get: (j) => j.seniority },
  { key: "source", label: "Source", get: (j) => j.source },
  { key: "company", label: "Company", get: (j) => j.company },
  { key: "location", label: "Location", get: (j) => j.location },
  { key: "salary", label: "Salary", get: (j) => fmtSalary(j), isSet: (j) => Boolean(j.salaryMin || j.salaryMax || j.salaryNote) },
  { key: "fit", label: "Fit score", get: (j) => j.fit?.score != null ? String(j.fit.score) : "", isSet: (j) => j.fit?.score != null },
  { key: "nextAction", label: "Next action", get: (j) => j.nextAction ? "Has follow-up" : "", isSet: (j) => Boolean(j.nextAction) },
];

function displayValue(value) {
  const text = String(value ?? "").trim();
  return text && text !== "—" && text.toLowerCase() !== "unknown" ? text : "";
}

function dynamicFieldIsSet(job, def) {
  if (def.isSet) return def.isSet(job);
  return Boolean(displayValue(def.get(job)));
}

function dynamicFieldValue(job, def) {
  return displayValue(def.get(job));
}

function dynamicFilterMatches(job, key, wanted) {
  const def = DYNAMIC_FILTER_DEFS.find(d => d.key === key);
  if (!def || !wanted || wanted === "All") return true;
  if (wanted === SET_VALUE) return dynamicFieldIsSet(job, def);
  if (wanted === NOT_SET_VALUE) return !dynamicFieldIsSet(job, def);
  return dynamicFieldValue(job, def) === wanted;
}

function dynamicFilterOptions(jobs, key) {
  const def = DYNAMIC_FILTER_DEFS.find(d => d.key === key);
  if (!def) return [SET_VALUE, NOT_SET_VALUE];
  const values = [...new Set(jobs.map(j => dynamicFieldValue(j, def)).filter(Boolean))].sort((a, b) =>
    String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: "base" })
  );
  return [SET_VALUE, NOT_SET_VALUE, ...values];
}

function filterIsActive(value) {
  if (Array.isArray(value)) return value.length > 0;
  return value != null && value !== "All";
}

function jobFitColor(score) {
  if (score == null) return "var(--fg-faint)";
  if (score >= 75) return "var(--st-offer)";
  if (score >= 50) return "var(--st-screening)";
  return "var(--st-rejected)";
}

function fmtSalaryPart(value, currency) {
  if (!value) return "—";
  const sym = { USD: "$", GBP: "£", EUR: "€", CAD: "C$", AUD: "A$" }[currency] || (currency ? currency + " " : "");
  const k = (n) => n >= 1000 ? `${Math.round(n / 1000)}k` : String(n);
  return `${sym}${k(value)}`;
}

function compareWarnings(job) {
  const warnings = [];
  if (!job.location || job.location === "—") warnings.push("No location");
  if (!(job.salaryMin || job.salaryMax || job.salaryNote)) warnings.push("No salary");
  if (!job.workMode || job.workMode === "—") warnings.push("No work mode");
  if (job.extraction?.status === "fail") warnings.push("Extraction failed");
  if (job.extraction?.status === "pending") warnings.push("Extraction pending");
  if ((job.rawByteSize || 0) < 1000 || (job.cleanedByteSize || 0) < 700) warnings.push("Short capture");
  return warnings;
}

function hasMissingAiFields(job) {
  return !job.location
    || job.location === "—"
    || !job.workMode
    || job.workMode === "—"
    || !(job.salaryMin || job.salaryMax || job.salaryNote)
    || job.extraction?.status === "pending"
    || job.extraction?.status === "fail";
}

function statusLabel(status) {
  return String(status || "").split("_").map(s => s ? s.charAt(0).toUpperCase() + s.slice(1) : s).join(" ");
}

function JobsToolbar({ q, setQ, searchRef, filters, setFilters, sourceOptions, dynamicOptions, visibleColumns, setVisibleColumns, sort, setSort, selectedCount, onOpenSelectedSources, onChangeSelectedStatus, onCompareSelected, onSaveView, currentViewName }) {
  const [columnsOpen, setColumnsOpen] = React.useState(false);
  const [sortOpen, setSortOpen] = React.useState(false);
  const [saveOpen, setSaveOpen] = React.useState(false);
  const [addFilterOpen, setAddFilterOpen] = React.useState(false);
  const [addFilterField, setAddFilterField] = React.useState(null);
  const [saveName, setSaveName] = React.useState("");
  const columnsRef = React.useRef(null);
  const sortRef = React.useRef(null);
  const saveRef = React.useRef(null);
  const addFilterRef = React.useRef(null);
  const columnsButtonRef = React.useRef(null);
  const sortButtonRef = React.useRef(null);
  const saveButtonRef = React.useRef(null);
  const addFilterButtonRef = React.useRef(null);

  // Close popovers on outside click
  React.useEffect(() => {
    function h(e) {
      if (columnsRef.current && !columnsRef.current.contains(e.target)) setColumnsOpen(false);
      if (sortRef.current && !sortRef.current.contains(e.target)) setSortOpen(false);
      if (saveRef.current && !saveRef.current.contains(e.target)) setSaveOpen(false);
      if (addFilterRef.current && !addFilterRef.current.contains(e.target)) setAddFilterOpen(false);
    }
    document.addEventListener("mousedown", h);
    return () => document.removeEventListener("mousedown", h);
  }, []);

  // Close popovers on Escape
  React.useEffect(() => {
    function h(e) {
      if (e.key !== "Escape") return;
      if (columnsOpen) { setColumnsOpen(false); columnsButtonRef.current?.focus(); }
      if (sortOpen) { setSortOpen(false); sortButtonRef.current?.focus(); }
      if (saveOpen) { setSaveOpen(false); saveButtonRef.current?.focus(); }
      if (addFilterOpen) { setAddFilterOpen(false); addFilterButtonRef.current?.focus(); }
    }
    document.addEventListener("keydown", h);
    return () => document.removeEventListener("keydown", h);
  }, [addFilterOpen, columnsOpen, saveOpen, sortOpen]);

  // Allow sidebar "New view" button to open this dialog
  React.useEffect(() => {
    window.JH_OPEN_SAVE_VIEW_DIALOG = () => setSaveOpen(true);
    return () => { delete window.JH_OPEN_SAVE_VIEW_DIALOG; };
  }, []);

  function confirmSave() {
    const name = saveName.trim();
    if (!name) return;
    onSaveView(name, { makeActive: true });
    setSaveName("");
    setSaveOpen(false);
  }

  function updateCurrentView() {
    if (!currentViewName) return;
    onSaveView(currentViewName, { makeActive: true });
    setSaveOpen(false);
  }

  const F = (key, label, val, options) => (
    <FilterPill
      label={label}
      value={val}
      active={filterIsActive(val)}
      onChange={(v) => setFilters({ ...filters, [key]: v })}
      options={options}
      onClear={() => setFilters({ ...filters, [key]: "All" })}
    />
  );

  const currentSortLabel = SORT_OPTIONS.find(o => o.key === sort.key)?.label || "Last captured";
  const dynamicFilters = filters.dynamic || {};

  return (
    <div className="jh-toolbar">
      <div className="jh-search">
        <Icon.Search size={13} className="ico" />
        <input
          ref={searchRef}
          placeholder="Search company, title, location, #id…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <span className="kbd">⌘K</span>
      </div>
      {FIXED_FILTER_DEFS.filter(def => filterIsActive(filters[def.key])).map(def =>
        F(def.key, def.label, filters[def.key], def.options({ sourceOptions }))
      )}
      {Object.entries(dynamicFilters).map(([key, value]) => {
        const def = DYNAMIC_FILTER_DEFS.find(d => d.key === key);
        if (!def) return null;
        return (
          <FilterPill
            key={key}
            label={def.label}
            value={value}
            active={true}
            onChange={(v) => setFilters({ ...filters, dynamic: { ...dynamicFilters, [key]: v } })}
            options={dynamicOptions[key] || [SET_VALUE, NOT_SET_VALUE]}
            onClear={() => {
              const next = { ...dynamicFilters };
              delete next[key];
              setFilters({ ...filters, dynamic: next });
            }}
          />
        );
      })}
      <DynamicFilterAdd
        refEl={addFilterRef}
        triggerRef={addFilterButtonRef}
        open={addFilterOpen}
        setOpen={setAddFilterOpen}
        field={addFilterField}
        setField={setAddFilterField}
        dynamicFilters={dynamicFilters}
        filters={filters}
        sourceOptions={sourceOptions}
        dynamicOptions={dynamicOptions}
        onAdd={(key, value) => {
          const fixed = FIXED_FILTER_DEFS.find(def => def.key === key);
          if (fixed) {
            setFilters({ ...filters, [key]: value });
            setAddFilterOpen(false);
            setAddFilterField(null);
            return;
          }
          setFilters({ ...filters, dynamic: { ...dynamicFilters, [key]: value } });
          setAddFilterOpen(false);
          setAddFilterField(null);
        }}
      />
      <div style={{ marginLeft: "auto", display: "flex", gap: 6 }}>
        {selectedCount > 0 && (
          <>
            <Btn
              kind="ghost"
              size="sm"
              icon={<Icon.Tag size={12} />}
              title={`Change status for ${selectedCount} selected job${selectedCount !== 1 ? "s" : ""}`}
              onClick={onChangeSelectedStatus}
            >
              Change status
            </Btn>
            <Btn
              kind="ghost"
              size="sm"
              icon={<Icon.External size={12} />}
              title={`Open source pages for ${selectedCount} selected job${selectedCount !== 1 ? "s" : ""}`}
              onClick={onOpenSelectedSources}
            >
              Open pages
            </Btn>
            {selectedCount > 1 && (
              <Btn
                kind="ghost"
                size="sm"
                icon={<Icon.Briefcase size={12} />}
                title={`Compare ${selectedCount} selected jobs`}
                onClick={onCompareSelected}
              >
                Compare
              </Btn>
            )}
          </>
        )}
        {/* Sort button */}
        <div ref={sortRef} style={{ position: "relative" }}>
          <Btn kind="ghost" size="sm" icon={<Icon.ArrowUpDown size={12} />}
            ref={sortButtonRef}
            active={sortOpen}
            aria-haspopup="menu"
            aria-expanded={sortOpen}
            onClick={() => { setSortOpen(v => !v); setColumnsOpen(false); }}>
            Sort{sort.key !== "capturedAt" || sort.dir !== "desc" ? `: ${currentSortLabel}` : ""}
          </Btn>
          {sortOpen && (
            <div className="jh-popover" style={{ position: "absolute", top: "100%", right: 0, marginTop: 4, zIndex: 100 }}>
              {SORT_OPTIONS.map(opt => (
                <div key={opt.key} style={{ padding: "2px 4px" }}>
                  <button
                    onClick={() => {
                      const newDir = sort.key === opt.key ? (sort.dir === "asc" ? "desc" : "asc") : "desc";
                      setSort({ key: opt.key, dir: newDir });
                      setSortOpen(false);
                    }}
                    style={{
                      display: "flex", alignItems: "center", justifyContent: "space-between",
                      width: "100%", padding: "5px 8px", borderRadius: 4, fontSize: 12.5,
                      background: sort.key === opt.key ? "var(--bg-hover)" : "transparent",
                      color: sort.key === opt.key ? "var(--fg-strong)" : "var(--fg)",
                      cursor: "pointer", gap: 16,
                    }}
                  >
                    <span style={{ display: "flex", alignItems: "center", gap: 6 }}>
                      {sort.key === opt.key ? <Icon.Check size={11} /> : <span style={{ width: 11 }}></span>}
                      {opt.label}
                    </span>
                    {sort.key === opt.key && (
                      <span style={{ fontSize: 11, color: "var(--fg-mute)", fontFamily: "var(--font-mono)" }}>
                        {sort.dir === "asc" ? "A→Z" : "Z→A"}
                      </span>
                    )}
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Columns button */}
        <div ref={columnsRef} style={{ position: "relative" }}>
          <Btn kind="ghost" size="sm" icon={<Icon.Eye size={12} />}
            ref={columnsButtonRef}
            active={columnsOpen}
            aria-haspopup="menu"
            aria-expanded={columnsOpen}
            onClick={() => { setColumnsOpen(v => !v); setSortOpen(false); }}>
            Columns
          </Btn>
          {columnsOpen && (
            <div className="jh-popover" style={{ position: "absolute", top: "100%", right: 0, marginTop: 4, zIndex: 100 }}>
              {ALL_COLUMNS.map(col => (
                <label key={col} style={{ display: "flex", gap: 8, padding: "4px 12px", cursor: "pointer", fontSize: 13, alignItems: "center" }}>
                  <input type="checkbox" checked={visibleColumns.includes(col)}
                    onChange={() => setVisibleColumns(prev =>
                      prev.includes(col) ? prev.filter(c => c !== col) : [...prev, col]
                    )} />
                  {COLUMN_LABELS[col]}
                </label>
              ))}
            </div>
          )}
        </div>

        {/* Save view button */}
        <div ref={saveRef} style={{ position: "relative" }}>
          <Btn kind="ghost" size="sm" icon={<Icon.Pin size={12} />}
            ref={saveButtonRef}
            active={saveOpen}
            aria-haspopup="dialog"
            aria-expanded={saveOpen}
            onClick={() => { setSaveOpen(v => !v); setColumnsOpen(false); setSortOpen(false); setSaveName(""); }}>
            Save view
          </Btn>
          {saveOpen && (
            <div className="jh-popover" style={{ position: "absolute", top: "100%", right: 0, marginTop: 4, zIndex: 100, padding: "10px 12px", minWidth: 240 }}>
              {currentViewName && (
                <div style={{ marginBottom: 10 }}>
                  <div style={{ fontSize: 11, color: "var(--fg-mute)", marginBottom: 6 }}>Current view</div>
                  <Btn size="sm" kind="accent" icon={<Icon.Check size={11} />} onClick={updateCurrentView}>
                    Update "{currentViewName}"
                  </Btn>
                </div>
              )}
              <div style={{ fontSize: 11, color: "var(--fg-mute)", marginBottom: 6 }}>{currentViewName ? "Save as new view" : "Name this view"}</div>
              <div style={{ display: "flex", gap: 6 }}>
                <input
                  autoFocus
                  value={saveName}
                  onChange={e => setSaveName(e.target.value)}
                  onKeyDown={e => { if (e.key === "Enter") confirmSave(); if (e.key === "Escape") setSaveOpen(false); }}
                  placeholder="e.g. High fit remote"
                  style={{ flex: 1, height: 28, padding: "0 8px", background: "var(--bg-elev)", border: "1px solid var(--border)", borderRadius: "var(--r-2)", color: "var(--fg)", fontSize: 12, outline: "none" }}
                />
                <Btn size="sm" kind="accent" onClick={confirmSave} disabled={!saveName.trim()}>Save</Btn>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function FilterPill({ label, value, options, onChange, onClear, active }) {
  const [open, setOpen] = React.useState(false);
  const ref = React.useRef(null);
  const buttonRef = React.useRef(null);
  React.useEffect(() => {
    function h(e) { if (ref.current && !ref.current.contains(e.target)) setOpen(false); }
    document.addEventListener("mousedown", h);
    return () => document.removeEventListener("mousedown", h);
  }, []);
  React.useEffect(() => {
    function h(e) {
      if (e.key !== "Escape" || !open) return;
      setOpen(false);
      buttonRef.current?.focus();
    }
    document.addEventListener("keydown", h);
    return () => document.removeEventListener("keydown", h);
  }, [open]);
  return (
    <div ref={ref} style={{ position: "relative" }}>
      <button ref={buttonRef} className="jh-filter" data-active={active || undefined} aria-haspopup="menu" aria-expanded={open} onClick={() => setOpen((v) => !v)}>
        <span className="label">{label}</span>
        <span className="val">{Array.isArray(value) ? value.join(", ") : value}</span>
        {active ? (
          <span onClick={(e) => { e.stopPropagation(); onClear(); }} style={{ marginLeft: 2, display: "inline-flex", padding: 1, color: "var(--fg-mute)" }}><Icon.X size={10} /></span>
        ) : (
          <Icon.ChevronDown size={10} />
        )}
      </button>
      {open && (
        <div style={{
          position: "absolute", top: 32, left: 0, zIndex: 50,
          background: "var(--bg-elev-2)", border: "1px solid var(--border-strong)",
          borderRadius: "var(--r-2)", boxShadow: "var(--shadow-popover)",
          minWidth: 180, padding: 4,
        }}>
          {options.map((o) => (
            <button
              key={o}
              onClick={() => { onChange(o); setOpen(false); }}
              style={{
                display: "flex", alignItems: "center", gap: 6, width: "100%",
                padding: "6px 8px", borderRadius: 4, fontSize: 12.5,
                color: o === value ? "var(--fg-strong)" : "var(--fg)",
                background: o === value ? "var(--bg-hover)" : "transparent",
                cursor: "pointer", textAlign: "left",
              }}
              onMouseEnter={(e) => { if (o !== value) e.currentTarget.style.background = "var(--bg-hover)"; }}
              onMouseLeave={(e) => { if (o !== value) e.currentTarget.style.background = "transparent"; }}
            >
              {o === value ? <Icon.Check size={11} /> : <span style={{ width: 11 }}></span>}
              <span>{o}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function DynamicFilterAdd({ refEl, triggerRef, open, setOpen, field, setField, dynamicFilters, filters, sourceOptions, dynamicOptions, onAdd }) {
  const fixedFields = FIXED_FILTER_DEFS
    .filter(def => !filterIsActive(filters[def.key]))
    .map(def => ({ ...def, kind: "fixed" }));
  const dynamicFields = DYNAMIC_FILTER_DEFS
    .filter(def => !(def.key in dynamicFilters))
    .map(def => ({ ...def, kind: "dynamic" }));
  const availableFields = [...fixedFields, ...dynamicFields];
  const selected = availableFields.find(def => def.key === field) || availableFields[0] || null;
  const options = selected
    ? selected.kind === "fixed"
      ? selected.options({ sourceOptions }).filter(v => v !== selected.reset)
      : (dynamicOptions[selected.key] || [SET_VALUE, NOT_SET_VALUE])
    : [];

  return (
    <div ref={refEl} style={{ position: "relative" }}>
      <button
        ref={triggerRef}
        className="jh-filter-add"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => {
          setField(selected?.key || null);
          setOpen((v) => !v);
        }}
      >
        <Icon.Plus size={11} />
        Filter
      </button>
      {open && (
        <div style={{
          position: "absolute", top: 32, left: 0, zIndex: 50,
          background: "var(--bg-elev-2)", border: "1px solid var(--border-strong)",
          borderRadius: "var(--r-2)", boxShadow: "var(--shadow-popover)",
          minWidth: 320, padding: 8, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8,
        }}>
          <div>
            <div style={{ fontSize: 11, color: "var(--fg-mute)", padding: "2px 4px 6px" }}>Column</div>
            <div style={{ display: "flex", flexDirection: "column", gap: 2, maxHeight: 260, overflow: "auto" }}>
              {availableFields.length === 0 ? (
                <div style={{ padding: 8, color: "var(--fg-mute)", fontSize: 12 }}>All filters are active.</div>
              ) : availableFields.map(def => (
                <button
                  key={def.key}
                  onClick={() => setField(def.key)}
                  style={{
                    display: "flex", alignItems: "center", gap: 6, width: "100%",
                    padding: "6px 8px", borderRadius: 4, fontSize: 12.5,
                    color: selected?.key === def.key ? "var(--fg-strong)" : "var(--fg)",
                    background: selected?.key === def.key ? "var(--bg-hover)" : "transparent",
                    cursor: "pointer", textAlign: "left",
                  }}
                >
                  {selected?.key === def.key ? <Icon.Check size={11} /> : <span style={{ width: 11 }}></span>}
                  <span>{def.label}</span>
                </button>
              ))}
            </div>
          </div>
          <div>
            <div style={{ fontSize: 11, color: "var(--fg-mute)", padding: "2px 4px 6px" }}>Value</div>
            <div style={{ display: "flex", flexDirection: "column", gap: 2, maxHeight: 260, overflow: "auto" }}>
              {options.map(value => (
                <button
                  key={value}
                  onClick={() => selected && onAdd(selected.key, value)}
                  style={{
                    display: "flex", alignItems: "center", gap: 6, width: "100%",
                    padding: "6px 8px", borderRadius: 4, fontSize: 12.5,
                    color: "var(--fg)", background: "transparent", cursor: "pointer", textAlign: "left",
                  }}
                  onMouseEnter={(e) => { e.currentTarget.style.background = "var(--bg-hover)"; }}
                  onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; }}
                >
                  <span style={{ width: 11 }}></span>
                  <span>{value}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function JobsPage({ selectedJobId, onSelectJob, panelOpen, savedViewName, setSavedViewName }) {
  const searchRef = React.useRef(null);
  const selectAllRef = React.useRef(null);
  const lastSelectionRef = React.useRef(null);
  const [q, setQ] = React.useState("");
  const [filters, setFilters] = React.useState({
    status: "All", minRating: "All", remote: "All", extraction: "All", source: "All", dup: "All", salary: "All", recentDays: null, dynamic: {},
  });
  const [sel, setSel] = React.useState(new Set());
  React.useEffect(() => { window.JH_SELECTED_JOB_IDS = [...sel]; window.JH_SET_SEL_COUNT?.(sel.size); return () => { window.JH_SELECTED_JOB_IDS = []; window.JH_SET_SEL_COUNT?.(0); }; }, [sel]);
  const [sort, setSort] = React.useState({ key: "capturedAt", dir: "desc" });
  const [currentViewName, setCurrentViewName] = React.useState(null);
  const [batchStatusDialog, setBatchStatusDialog] = React.useState(false);
  const [batchAiDialog, setBatchAiDialog] = React.useState(false);
  const [compareDialog, setCompareDialog] = React.useState(false);

  // Column visibility with localStorage persistence
  const [visibleColumns, setVisibleColumns] = React.useState(() => {
    try {
      const saved = localStorage.getItem("jobhunt.columns");
      if (!saved) return DEFAULT_COLUMNS;
      const parsed = JSON.parse(saved);
      if (!Array.isArray(parsed)) return DEFAULT_COLUMNS;
      if (!parsed.includes("processed")) {
        const capturedIndex = parsed.indexOf("captured");
        const next = [...parsed];
        next.splice(capturedIndex === -1 ? next.length : capturedIndex + 1, 0, "processed");
        const normalized = next.flatMap(c => c === "salary" ? ["salaryMin", "salaryMax"] : [c]).filter(c => ALL_COLUMNS.includes(c));
        if (!normalized.includes("lastOpened")) {
          const normalizedCapturedIndex = normalized.indexOf("captured");
          normalized.splice(normalizedCapturedIndex === -1 ? normalized.length : normalizedCapturedIndex + 1, 0, "lastOpened");
        }
        return normalized;
      }
      const next = parsed.flatMap(c => c === "salary" ? ["salaryMin", "salaryMax"] : [c]).filter(c => ALL_COLUMNS.includes(c));
      if (!next.includes("lastOpened")) {
        const capturedIndex = next.indexOf("captured");
        next.splice(capturedIndex === -1 ? next.length : capturedIndex + 1, 0, "lastOpened");
      }
      return next;
    } catch { return DEFAULT_COLUMNS; }
  });
  React.useEffect(() => {
    localStorage.setItem("jobhunt.columns", JSON.stringify(visibleColumns));
  }, [visibleColumns]);

  // Real indeterminate property on select-all checkbox
  React.useEffect(() => {
    if (selectAllRef.current) {
      selectAllRef.current.indeterminate = someSel;
    }
  }, [sel, filtered]);

  // Expose focus function so the global Cmd+K handler in app.jsx can call it
  React.useEffect(() => {
    window.JH_FOCUS_JOBS_SEARCH = () => { searchRef.current?.focus(); searchRef.current?.select(); };
    return () => { delete window.JH_FOCUS_JOBS_SEARCH; };
  }, []);

  React.useEffect(() => {
    function applyPendingSelection() {
      const ids = Array.isArray(window.JH_PENDING_SELECTED_JOB_IDS) ? window.JH_PENDING_SELECTED_JOB_IDS : [];
      if (ids.length === 0) return;
      const validIds = new Set(jobs.map((j) => j.id));
      setSel(new Set(ids.filter((id) => validIds.has(id))));
      delete window.JH_PENDING_SELECTED_JOB_IDS;
    }
    applyPendingSelection();
    window.addEventListener("jobhunt:select-jobs", applyPendingSelection);
    return () => window.removeEventListener("jobhunt:select-jobs", applyPendingSelection);
  }, [jobs]);

  function applySavedViewToState(view) {
    if (view === "active") {
      setFilters(f => ({ ...f, status: ["applied", "interview", "offer"] }));
      setCurrentViewName(null);
    } else if (view === "remote") {
      setFilters(f => ({ ...f, remote: "Yes" }));
      setCurrentViewName(null);
    } else if (view === "recent") {
      setFilters(f => ({ ...f, recentDays: 7 }));
      setCurrentViewName(null);
    } else {
      const custom = loadSavedViews().find(v => v.name === view);
      if (custom) {
        setFilters(custom.filters);
        if (custom.sort) setSort(custom.sort);
        if (custom.q !== undefined) setQ(custom.q);
        setCurrentViewName(custom.name);
      }
    }
  }

  // Register saved view handler (built-in + custom)
  React.useEffect(() => {
    window.JH_APPLY_SAVED_VIEW = (view) => {
      applySavedViewToState(view);
    };
    if (window.JH_PENDING_SAVED_VIEW) {
      window.JH_APPLY_SAVED_VIEW(window.JH_PENDING_SAVED_VIEW);
      delete window.JH_PENDING_SAVED_VIEW;
    }
    return () => { delete window.JH_APPLY_SAVED_VIEW; };
  }, []);

  const prevSavedViewName = React.useRef(savedViewName);
  React.useEffect(() => {
    if (savedViewName) {
      applySavedViewToState(savedViewName);
    } else if (prevSavedViewName.current) {
      // Transitioned from a saved view back to "all jobs" — reset filters to defaults.
      setQ("");
      setFilters({ status: "All", minRating: "All", remote: "All", extraction: "All", source: "All", dup: "All", salary: "All", recentDays: null, dynamic: {} });
      setSort({ key: "capturedAt", dir: "desc" });
      setCurrentViewName(null);
    }
    prevSavedViewName.current = savedViewName;
  }, [savedViewName]); // eslint-disable-line react-hooks/exhaustive-deps

  function handleSaveView(name, { makeActive = false } = {}) {
    const views = loadSavedViews().filter(v => v.name !== name);
    views.push({ name, filters, sort, q });
    persistSavedViews(views);
    if (makeActive) {
      setCurrentViewName(name);
      setSavedViewName?.(name);
    }
    window.JH_TOAST?.show(`View "${name}" saved`, "info");
  }

  const jobs = window.JH_JOBS;
  const sourceOptions = [...new Set(jobs.map((j) => j.source).filter(Boolean))].sort();
  const dynamicOptions = Object.fromEntries(DYNAMIC_FILTER_DEFS.map(def => [def.key, dynamicFilterOptions(jobs, def.key)]));

  const filtered = jobs.filter((j) => {
    if (q) {
      const qLow = q.toLowerCase().trim();
      const matchNum = qLow.startsWith("#") ? qLow.slice(1) : qLow;
      const textMatch = `${j.company} ${j.title} ${j.location}`.toLowerCase().includes(qLow);
      const numMatch = String(j.jobNumber) === matchNum || String(j.jobNumber).includes(matchNum);
      if (!textMatch && !numMatch) return false;
    }
    if (Array.isArray(filters.status)) {
      if (!filters.status.includes(j.status)) return false;
    } else if (filters.status !== "All" && j.status !== filters.status.toLowerCase().replace(/ /g, "_")) return false;
    if (filters.remote !== "All" && j.remote !== filters.remote) return false;
    if (filters.extraction !== "All") {
      const extMap = { OK: "ok", Pending: "pending", Failed: "fail" };
      if (j.extraction.status !== (extMap[filters.extraction] ?? filters.extraction)) return false;
    }
    if (filters.source !== "All" && j.source !== filters.source) return false;
    if (filters.dup === "Has candidate" && !j.hasDuplicate) return false;
    if (filters.dup === "No candidate" && j.hasDuplicate) return false;
    if (filters.minRating !== "All") {
      const minR = parseInt(filters.minRating.replace(/[^\d]/g, ""), 10);
      if ((j.rating || 0) < minR) return false;
    }
    if (filters.salary !== "All") {
      if (filters.salary === SET_VALUE && !(j.salaryMin || j.salaryMax || j.salaryNote)) return false;
      if (filters.salary === NOT_SET_VALUE && (j.salaryMin || j.salaryMax || j.salaryNote)) return false;
      if (filters.salary === SET_VALUE || filters.salary === NOT_SET_VALUE) return true;
      const m = parseInt(filters.salary.replace(/[^\d]/g, ""), 10) * 1000;
      if ((j.salaryMax || j.salaryMin || 0) < m) return false;
    }
    if (filters.recentDays) {
      if (daysFrom(j.capturedAt.slice(0, 10)) < -filters.recentDays) return false;
    }
    for (const [key, value] of Object.entries(filters.dynamic || {})) {
      if (!dynamicFilterMatches(j, key, value)) return false;
    }
    return true;
  });

  function sortValue(job, key) {
    if (key === "salaryMin") return job.salaryMin || job.salaryMax || 0;
    if (key === "salaryMax") return job.salaryMax || job.salaryMin || 0;
    if (key === "rating") return job.rating || 0;
    if (key === "fitScore") return job.fit?.score ?? -1;
    if (key === "extractionStatus") return job.extraction?.status || "";
    if (key === "lastProcessedAt") return job.extraction?.at || "";
    if (key === "lastOpenedAt") return job.lastOpenedAt || "";
    if (key === "nextActionDue") return job.nextAction?.dueDate || "";
    return job[key] ?? "";
  }

  filtered.sort((a, b) => {
    const av = sortValue(a, sort.key);
    const bv = sortValue(b, sort.key);
    const aEmpty = av == null || av === "" || av === "—";
    const bEmpty = bv == null || bv === "" || bv === "—";
    if (aEmpty && bEmpty) return 0;
    if (aEmpty) return 1;
    if (bEmpty) return -1;
    const cmp = typeof av === "number" && typeof bv === "number"
      ? av - bv
      : String(av).localeCompare(String(bv), undefined, { numeric: true, sensitivity: "base" });
    return sort.dir === "asc" ? cmp : -cmp;
  });

  const allSel = sel.size > 0 && filtered.every((j) => sel.has(j.id));
  const someSel = sel.size > 0 && !allSel;
  const selectedJobs = jobs.filter((j) => sel.has(j.id));
  const selectedMissingAiCount = selectedJobs.filter(hasMissingAiFields).length;

  function toggle(id, checked, shiftKey = false) {
    const nextChecked = checked ?? !sel.has(id);
    if (shiftKey && lastSelectionRef.current) {
      const start = filtered.findIndex((j) => j.id === lastSelectionRef.current);
      const end = filtered.findIndex((j) => j.id === id);
      if (start !== -1 && end !== -1) {
        const next = new Set(sel);
        const [from, to] = start < end ? [start, end] : [end, start];
        filtered.slice(from, to + 1).forEach((j) => {
          if (nextChecked) next.add(j.id);
          else next.delete(j.id);
        });
        setSel(next);
        lastSelectionRef.current = id;
        return;
      }
    }
    const next = new Set(sel);
    if (nextChecked) next.add(id); else next.delete(id);
    setSel(next);
    lastSelectionRef.current = id;
  }
  function toggleAll() {
    if (allSel) setSel(new Set());
    else setSel(new Set(filtered.map((j) => j.id)));
    lastSelectionRef.current = null;
  }

  function sortBy(key) {
    setSort((s) => s.key === key ? { key, dir: s.dir === "asc" ? "desc" : "asc" } : { key, dir: "desc" });
  }

  function openSelectedSources() {
    const selectedJobs = jobs.filter((j) => sel.has(j.id));
    const sourceJobs = selectedJobs.filter((j) => j.sourceUrl);
    const urls = [...new Set(sourceJobs.map((j) => j.sourceUrl))];
    let opened = 0;
    for (const url of urls) {
      const a = document.createElement("a");
      a.href = url;
      a.target = "_blank";
      a.rel = "noopener";
      a.style.display = "none";
      document.body.appendChild(a);
      a.click();
      a.remove();
      opened++;
    }
    if (urls.length === 0) {
      window.JH_TOAST?.show("No selected jobs have source pages", "error");
    } else {
      window.JH_TOAST?.show(`Opened ${opened} source page${opened !== 1 ? "s" : ""}`);
      Promise.all(sourceJobs.map((j) => window.JH_API.api(`/api/jobs/${j.id}/opened`, { method: "POST" })))
        .then(() => window.JH_REFRESH_UI_DATA?.())
        .catch((e) => window.JH_TOAST?.show(e.message, "error"));
    }
  }

  const col = (name) => visibleColumns.includes(name);

  function SortH({ k, children, right }) {
    const active = sort.key === k;
    return (
      <th
        className="sortable"
        style={right ? { textAlign: "right" } : undefined}
        onClick={() => sortBy(k)}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); sortBy(k); } }}
        tabIndex={0}
        aria-sort={active ? (sort.dir === "asc" ? "ascending" : "descending") : "none"}
      >
        <span>
          {children}
          {active && (sort.dir === "asc" ? <Icon.ChevronDown size={10} style={{ transform: "rotate(180deg)" }} /> : <Icon.ChevronDown size={10} />)}
        </span>
      </th>
    );
  }

  return (
    <>
      <JobsToolbar
        q={q} setQ={setQ} searchRef={searchRef}
        filters={filters} setFilters={setFilters}
        sourceOptions={sourceOptions}
        dynamicOptions={dynamicOptions}
        visibleColumns={visibleColumns} setVisibleColumns={setVisibleColumns}
        sort={sort} setSort={setSort}
        selectedCount={sel.size}
        onOpenSelectedSources={openSelectedSources}
        onChangeSelectedStatus={() => setBatchStatusDialog(true)}
        onCompareSelected={() => setCompareDialog(true)}
        onSaveView={handleSaveView}
        currentViewName={currentViewName}
      />

      {window.JH_META && window.JH_META.total_jobs > window.JH_META.loaded_jobs && (
        <div className="jh-truncation-warn">
          Showing {window.JH_META.loaded_jobs} of {window.JH_META.total_jobs} jobs. Search and filters apply to loaded rows only.
        </div>
      )}

      <div className="jh-tablewrap" style={{ position: "relative" }}>
        <table className="jh-table" style={{ tableLayout: "fixed" }}>
          <colgroup>
            <col style={{ width: 28 }} />
            <col style={{ width: 58 }} />
            {col("status") && <col style={{ width: 100 }} />}
            {col("rating") && <col style={{ width: 80 }} />}
            {col("fit") && <col style={{ width: 54 }} />}
            {col("company") && <col style={{ width: panelOpen ? 140 : 170 }} />}
            {col("title") && <col style={{ width: panelOpen ? 220 : 265 }} />}
            {col("location") && !panelOpen && <col style={{ width: 140 }} />}
            {col("remote") && <col style={{ width: 70 }} />}
            {col("salaryMin") && <col style={{ width: 90 }} />}
            {col("salaryMax") && <col style={{ width: 90 }} />}
            {col("seniority") && <col style={{ width: 90 }} />}
            {col("employment") && <col style={{ width: 90 }} />}
            {col("source") && !panelOpen && <col style={{ width: 90 }} />}
            {col("captured") && <col style={{ width: 96 }} />}
            {col("lastOpened") && <col style={{ width: 96 }} />}
            {col("processed") && <col style={{ width: 96 }} />}
            {col("extraction") && <col style={{ width: 80 }} />}
            {!panelOpen && <col style={{ width: panelOpen ? 0 : 200 }} />}
          </colgroup>
          <thead>
            <tr>
              <th>
                <input type="checkbox" className="jh-checkbox"
                  ref={selectAllRef}
                  checked={allSel}
                  onChange={toggleAll}
                  aria-label="Select all jobs"
                />
              </th>
              <SortH k="jobNumber">ID</SortH>
              {col("status") && <SortH k="status">Status</SortH>}
              {col("rating") && <SortH k="rating">Rating</SortH>}
              {col("fit") && <SortH k="fitScore" right>Fit</SortH>}
              {col("company") && <SortH k="company">Company</SortH>}
              {col("title") && <SortH k="title">Title</SortH>}
              {col("location") && !panelOpen && <SortH k="location">Location</SortH>}
              {col("remote") && <SortH k="remote">Criteria</SortH>}
              {col("salaryMin") && <SortH k="salaryMin" right>Salary min</SortH>}
              {col("salaryMax") && <SortH k="salaryMax" right>Salary max</SortH>}
              {col("seniority") && <SortH k="seniority">Seniority</SortH>}
              {col("employment") && <SortH k="employment">Employment</SortH>}
              {col("source") && !panelOpen && <SortH k="source">Source</SortH>}
              {col("captured") && <SortH k="capturedAt">Captured</SortH>}
              {col("lastOpened") && <SortH k="lastOpenedAt">Opened</SortH>}
              {col("processed") && <SortH k="lastProcessedAt">Processed</SortH>}
              {col("extraction") && <SortH k="extractionStatus">Extract</SortH>}
              {!panelOpen && <SortH k="nextActionDue">Next action</SortH>}
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 && (
              <tr>
                <td colSpan={20} style={{ padding: "48px 24px", textAlign: "center" }}>
                  {jobs.length === 0 ? (
                    <div className="jh-empty">
                      <Icon.Inbox size={20} />
                      <strong>No jobs captured yet</strong>
                      <span>Use the Chrome extension to capture job postings, or POST directly to <code>/captures</code>. See <code>extension/</code> to install the extension.</span>
                    </div>
                  ) : (
                    <div className="jh-empty">
                      <Icon.Search size={20} />
                      <strong>No jobs match your filters</strong>
                      <Btn size="sm" kind="ghost" onClick={() => {
                        setQ("");
                        setFilters({ status: "All", minRating: "All", remote: "All", extraction: "All", source: "All", dup: "All", salary: "All", recentDays: null, dynamic: {} });
                      }}>Clear filters</Btn>
                    </div>
                  )}
                </td>
              </tr>
            )}
            {filtered.map((j) => (
              <tr
                key={j.id}
                tabIndex={0}
                role="row"
                aria-selected={selectedJobId === j.id}
                data-selected={sel.has(j.id) || undefined}
                aria-current={selectedJobId === j.id ? "true" : undefined}
                onClick={() => onSelectJob(j.id)}
                onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onSelectJob(j.id); } }}
              >
                <td onClick={(e) => e.stopPropagation()} className="col-shrink">
                  <input
                    type="checkbox"
                    className="jh-checkbox"
                    checked={sel.has(j.id)}
                    onChange={(e) => toggle(j.id, e.target.checked, e.nativeEvent.shiftKey)}
                  />
                </td>
                <td className="col-mono">#{j.jobNumber}</td>
                {col("status") && <td><StatusChip value={j.status} /></td>}
                {col("rating") && <td><StarRating value={j.rating} readonly={true} size={12} /></td>}
                {col("fit") && (
                  <td className="col-mono" style={{ textAlign: "right" }}>
                    {j.fit?.status === "succeeded" && j.fit?.score != null ? (
                      <span style={{ color: jobFitColor(j.fit.score), fontWeight: 600 }} title={j.fit.summary || undefined}>{j.fit.score}</span>
                    ) : j.fit?.status === "pending" && j.fit?.score != null ? (
                      <span style={{ color: jobFitColor(j.fit.score), fontWeight: 600, opacity: 0.65 }} title="Previous fit score; re-scoring queued">{j.fit.score}</span>
                    ) : j.fit?.status === "pending" ? (
                      <span style={{ color: "var(--fg-faint)" }} title="Scoring queued">…</span>
                    ) : j.fit?.status === "failed" ? (
                      <span style={{ color: "var(--st-rejected)" }} title={j.fit.error || "Fit scoring failed"}>!</span>
                    ) : (
                      <span style={{ color: "var(--fg-faint)" }}>—</span>
                    )}
                  </td>
                )}
                {col("company") && <td><CompanyCell name={j.company} url={j.sourceUrl} /></td>}
                {col("title") && (
                  <td className="col-co" title={j.title}>
                    <span style={{ display: "inline-flex", alignItems: "center", gap: 4, maxWidth: "100%" }}>
                      <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{j.title}</span>
                      <button className="jh-btn jh-btn--ghost jh-btn--icon jh-btn--sm" style={{ flexShrink: 0, opacity: 0.5 }} title="Open source" aria-label="Open source" onClick={(e) => { e.stopPropagation(); window.JH_API.openJobSource(j.id, j.sourceUrl); }}><Icon.External size={10} /></button>
                    </span>
                  </td>
                )}
                {col("location") && !panelOpen && <td className="col-mute" title={j.location}>{j.location}</td>}
                {col("remote") && <td className="col-mute" title={`Work mode: ${j.workMode}`}>{j.remote}</td>}
                {col("salaryMin") && <td className="col-mono" style={{ textAlign: "right" }} title={j.salaryNote || fmtSalary(j)}>{fmtSalaryPart(j.salaryMin, j.currency)}</td>}
                {col("salaryMax") && <td className="col-mono" style={{ textAlign: "right" }} title={j.salaryNote || fmtSalary(j)}>{fmtSalaryPart(j.salaryMax, j.currency)}</td>}
                {col("seniority") && <td className="col-mute">{j.seniority || "—"}</td>}
                {col("employment") && <td className="col-mute">{j.employment || "—"}</td>}
                {col("source") && !panelOpen && <td className="col-mute"><span className="jh-tag">{j.source}</span></td>}
                {col("captured") && <td className="col-mono" title={fmtDateTime(j.capturedAt)}>{fmtCaptured(j.capturedAt)}</td>}
                {col("lastOpened") && <td className="col-mono" title={fmtDateTime(j.lastOpenedAt)}>{fmtCaptured(j.lastOpenedAt)}</td>}
                {col("processed") && <td className="col-mono" title={fmtDateTime(j.extraction?.at)}>{fmtCaptured(j.extraction?.at)}</td>}
                {col("extraction") && <td><ExtractionChip ext={j.extraction} /></td>}
                {!panelOpen && (
                  <td className="col-mute">
                    {j.nextAction ? (
                      <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                        <span className="jh-due" data-state={dueState(j.nextAction.dueDate)}>
                          <Icon.Clock size={11} />{dueLabel(j.nextAction.dueDate)}
                        </span>
                        <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{j.nextAction.note}</span>
                      </span>
                    ) : <span style={{ color: "var(--fg-faint)" }}>—</span>}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>

        {batchStatusDialog && (
          <AppSelectDialog
            title="Change status"
            options={window.JH_STATUSES.map(s => ({ value: s, label: statusLabel(s) }))}
            onConfirm={(status) => {
              const count = sel.size;
              setBatchStatusDialog(false);
              window.JH_API.bulkSetStatus([...sel], status)
                .then(() => { window.JH_TOAST.show(`${count} job${count !== 1 ? "s" : ""} updated to ${status}`); setSel(new Set()); return window.JH_REFRESH_UI_DATA(); })
                .catch(e => window.JH_TOAST.show(e.message, "error"));
            }}
            onClose={() => setBatchStatusDialog(false)}
          />
        )}
        {batchAiDialog && (
          <AppDialog
            title="Queue AI work"
            maxWidth={520}
            onClose={() => setBatchAiDialog(false)}
            actions={[
              { label: "Cancel", kind: "ghost", onClick: () => setBatchAiDialog(false) },
            ]}
          >
            <div style={{ display: "grid", gap: 8 }}>
              <button
                className="jh-filter"
                style={{ justifyContent: "space-between", padding: "10px 12px" }}
                onClick={() => {
                  const ids = selectedJobs.filter(hasMissingAiFields).map((job) => job.id);
                  window.JH_API.bulkQueueLlm(ids, "missing_fields")
                    .then(() => {
                      window.JH_TOAST.show(`${ids.length} job${ids.length !== 1 ? "s" : ""} queued for missing-field extraction`);
                      setBatchAiDialog(false);
                      setSel(new Set());
                      return window.JH_REFRESH_UI_DATA();
                    })
                    .catch((e) => window.JH_TOAST.show(e.message, "error"));
                }}
                disabled={selectedMissingAiCount === 0}
              >
                <span>
                  <strong>Missing fields only</strong>
                  <span style={{ display: "block", color: "var(--fg-mute)", fontSize: 11 }}>Location, work mode, salary, pending, or failed extraction</span>
                </span>
                <span className="col-mono">{selectedMissingAiCount}</span>
              </button>
              <button
                className="jh-filter"
                style={{ justifyContent: "space-between", padding: "10px 12px" }}
                onClick={() => {
                  const ids = [...sel];
                  window.JH_API.bulkQueueLlm(ids, "fit_score")
                    .then(() => {
                      window.JH_TOAST.show(`${ids.length} job${ids.length !== 1 ? "s" : ""} queued for fit scoring`);
                      setBatchAiDialog(false);
                      setSel(new Set());
                      return window.JH_REFRESH_UI_DATA();
                    })
                    .catch((e) => window.JH_TOAST.show(e.message, "error"));
                }}
              >
                <span>
                  <strong>Fit score only</strong>
                  <span style={{ display: "block", color: "var(--fg-mute)", fontSize: 11 }}>Use current extracted job details; skip re-parsing</span>
                </span>
                <span className="col-mono">{sel.size}</span>
              </button>
              <button
                className="jh-filter"
                style={{ justifyContent: "space-between", padding: "10px 12px" }}
                onClick={() => {
                  const ids = [...sel];
                  window.JH_API.bulkQueueLlm(ids, "extract")
                    .then(() => {
                      window.JH_TOAST.show(`${ids.length} job${ids.length !== 1 ? "s" : ""} queued for full extraction`);
                      setBatchAiDialog(false);
                      setSel(new Set());
                      return window.JH_REFRESH_UI_DATA();
                    })
                    .catch((e) => window.JH_TOAST.show(e.message, "error"));
                }}
              >
                <span>
                  <strong>Full extraction</strong>
                  <span style={{ display: "block", color: "var(--fg-mute)", fontSize: 11 }}>Re-parse all extracted fields from the captured JD</span>
                </span>
                <span className="col-mono">{sel.size}</span>
              </button>
            </div>
          </AppDialog>
        )}
        {compareDialog && (
          <AppDialog
            title="Compare selected jobs"
            maxWidth={920}
            onClose={() => setCompareDialog(false)}
            actions={[{ label: "Close", kind: "ghost", onClick: () => setCompareDialog(false) }]}
          >
            <div className="jh-tablewrap" style={{ maxHeight: "60vh", overflow: "auto" }}>
              <table className="jh-table" style={{ tableLayout: "fixed", minWidth: 820 }}>
                <colgroup>
                  <col style={{ width: 64 }} />
                  <col style={{ width: 170 }} />
                  <col />
                  <col style={{ width: 68 }} />
                  <col style={{ width: 130 }} />
                  <col style={{ width: 170 }} />
                  <col style={{ width: 90 }} />
                  <col style={{ width: 190 }} />
                </colgroup>
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Company</th>
                    <th>Title</th>
                    <th>Fit</th>
                    <th>Salary</th>
                    <th>Location</th>
                    <th>Criteria</th>
                    <th>Warnings</th>
                  </tr>
                </thead>
                <tbody>
                  {selectedJobs.map((job) => {
                    const warnings = compareWarnings(job);
                    return (
                      <tr key={job.id}>
                        <td className="col-mono">#{job.jobNumber}</td>
                        <td><CompanyCell name={job.company} url={job.sourceUrl} /></td>
                        <td className="col-co" title={job.title}>{job.title}</td>
                        <td className="col-mono" style={{ textAlign: "right", color: job.fit?.score != null ? jobFitColor(job.fit.score) : "var(--fg-faint)" }}>{job.fit?.score ?? "—"}</td>
                        <td className="col-mono" title={job.salaryNote || fmtSalary(job)}>{fmtSalary(job)}</td>
                        <td className="col-mute" title={job.location}>{job.location}</td>
                        <td className="col-mute">{job.remote}</td>
                        <td>
                          {warnings.length ? (
                            <span style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
                              {warnings.map((warning) => <span key={warning} className="jh-tag">{warning}</span>)}
                            </span>
                          ) : (
                            <span style={{ color: "var(--fg-faint)" }}>—</span>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </AppDialog>
        )}
        {sel.size > 0 && (
          <div className="jh-batch">
            <span className="jh-batch__count">{sel.size} selected</span>
            <span className="jh-batch__sep"></span>
            <Btn kind="ghost" size="sm" icon={<Icon.Tag size={11} />} onClick={() => setBatchStatusDialog(true)}>Change status</Btn>
            {sel.size > 1 && (
              <Btn kind="ghost" size="sm" icon={<Icon.Briefcase size={11} />} onClick={() => setCompareDialog(true)}>Compare</Btn>
            )}
            <Btn kind="ghost" size="sm" icon={<Icon.Sparkles size={11} />}
              title="Queue extraction, missing-field extraction, or fit scoring"
              onClick={() => setBatchAiDialog(true)}>Queue AI</Btn>
            <Btn kind="ghost" size="sm" icon={<Icon.Archive size={11} />} onClick={() => {
              const count = sel.size;
              Promise.all([...sel].map((id) => window.JH_API.api(`/api/jobs/${id}/archive`, { method: "POST" })))
                .then(() => { window.JH_TOAST.show(`${count} job${count !== 1 ? "s" : ""} archived`); setSel(new Set()); return window.JH_REFRESH_UI_DATA(); })
                .catch((e) => window.JH_TOAST.show(e.message, "error"));
            }}>Archive</Btn>
            <Btn kind="ghost" size="sm" icon={<Icon.External size={11} />} onClick={() => window.open("/exports/jobs.csv", "_blank")}>Export</Btn>
            <span className="jh-batch__sep"></span>
            <Btn kind="ghost" size="sm" aria-label="Clear selection" onClick={() => setSel(new Set())} icon={<Icon.X size={11} />} />
          </div>
        )}
      </div>
    </>
  );
}

Object.assign(window, { JobsPage });
