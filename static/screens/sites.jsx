// Jobhunt — Sites page

const SITE_REVIEW_STATES = [
  ["not_reviewed", "Not Reviewed"],
  ["reviewed", "Reviewed"],
  ["exclude", "Exclude"],
];

function EditableSiteField({ value, onSave, multiline = false, asLink = false, placeholder = "—" }) {
  const [editing, setEditing] = React.useState(false);
  const [draft, setDraft] = React.useState(value || "");
  const inputRef = React.useRef(null);
  const text = (value || "").trim();

  React.useEffect(() => {
    if (editing && inputRef.current) inputRef.current.focus();
  }, [editing]);

  const cancel = () => {
    setEditing(false);
    setDraft(value || "");
  };

  const commit = () => {
    const next = (draft || "").trim();
    setEditing(false);
    if (next === text) return;
    onSave(next).catch((error) => window.JH_TOAST.show(error.message, "error"));
  };

  if (editing) {
    if (multiline) {
      return (
        <textarea
          ref={inputRef}
          className="jh-input"
          rows={4}
          style={{ width: "100%", minWidth: 0, resize: "vertical", marginBottom: 4, height: "auto", boxSizing: "border-box" }}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === "Escape") { e.stopPropagation(); cancel(); }
            else if (e.key === "Enter" && e.ctrlKey) commit();
          }}
        />
      );
    }
    return (
      <input
        ref={inputRef}
        className="jh-input"
        style={{ fontSize: "inherit", width: "100%", minWidth: 0, flex: "1 1 auto", boxSizing: "border-box" }}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === "Enter") commit();
          if (e.key === "Escape") { e.stopPropagation(); cancel(); }
        }}
      />
    );
  }

  // URL field: show link to open + pencil button to edit
  if (asLink) {
    return (
      <span style={{ display: "flex", alignItems: "flex-start", gap: 4, minWidth: 0, width: "100%" }}>
        {text ? (
          <a
            href={text}
            target="_blank"
            rel="noreferrer"
            style={{ minWidth: 0, flex: 1, wordBreak: "break-all" }}
          >
            {text}
          </a>
        ) : (
          <span style={{ color: "var(--fg-faint)", flex: 1 }}>{placeholder}</span>
        )}
        <Btn
          size="sm"
          kind="ghost"
          icon={<Icon.Pencil size={11} />}
          title="Edit"
          style={{ flexShrink: 0, marginTop: 1 }}
          onClick={() => { setDraft(value || ""); setEditing(true); }}
        />
      </span>
    );
  }

  return (
    <span
      className="editable"
      style={{ cursor: "text" }}
      title="Click to edit"
      onClick={() => {
        setDraft(value || "");
        setEditing(true);
      }}
    >
      {text || placeholder}
    </span>
  );
}

function findSiteById(siteId) {
  const normalizedSiteId = siteId == null ? siteId : String(siteId);
  return (window.JH_SITES || []).find((row) => String(row.id) === normalizedSiteId || row.origin === siteId);
}

function SiteDetail({ siteId, onClose }) {
  const [site, setSite] = React.useState(() => findSiteById(siteId));
  const [nextReviewDialog, setNextReviewDialog] = React.useState(false);
  const [intervalDialog, setIntervalDialog] = React.useState(false);
  const [noteDialog, setNoteDialog] = React.useState(false);

  React.useEffect(() => {
    const refreshEvent = window.JH_SITE_UI_REFRESH_EVENT || "jobhunt:ui-data-refreshed";
    const refreshFromStore = () => setSite(findSiteById(siteId));
    refreshFromStore();
    const handler = () => refreshFromStore();
    window.addEventListener(refreshEvent, handler);
    return () => window.removeEventListener(refreshEvent, handler);
  }, [siteId]);

  React.useEffect(() => {
    const handler = (e) => {
      if (e.key !== "Escape") return;
      const tag = document.activeElement?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
      onClose();
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [onClose]);

  if (!site) return null;

  const siteRef = site.id || site.origin;
  const siteUrl = site.siteUrl || site.origin;

  return (
    <div className="jh-panel">
      <div className="jh-panel__head">
        <div className="jh-panel__hrow">
          <span className="jh-panel__co">
            <span className="logo">{site.origin ? site.origin.slice(0, 2).toUpperCase() : "?"}</span>
            <span>{site.origin}</span>
          </span>
          <Btn
            size="sm"
            kind="ghost"
            icon={<Icon.X size={11} />}
            title="Close"
            aria-label="Close site details"
            onClick={onClose}
            style={{ marginLeft: "auto" }}
          />
        </div>
        <div className="jh-panel__title">{site.pageTitle || site.origin}</div>
        <div className="jh-panel__sub">
          <span>Interval: {site.intervalDays}d</span>
          <span className="sep">·</span>
          <span>Last review: {site.lastReviewed || "—"}</span>
        </div>
        <div className="jh-panel__actions">
          <Btn size="sm" kind="ghost" icon={<Icon.Check size={11} />} title="Mark reviewed today" aria-label="Mark reviewed today" onClick={() => window.JH_API.reviewSite(siteRef).catch((e) => window.JH_TOAST.show(e.message, "error"))} />
          <Btn size="sm" kind="ghost" icon={<Icon.Calendar size={11} />} title="Set next review" aria-label="Set next review" onClick={() => setNextReviewDialog(true)} />
          <Btn size="sm" kind="ghost" icon={<Icon.Clock size={11} />} title="Set interval" aria-label="Set interval" onClick={() => setIntervalDialog(true)} />
          <Btn size="sm" kind="ghost" icon={<Icon.Note size={11} />} title="Set note" aria-label="Set note" onClick={() => setNoteDialog(true)} />
          <Btn size="sm" kind="ghost" icon={<Icon.External size={11} />} title="Open site" aria-label="Open site" onClick={() => window.open(siteUrl, "_blank")} />
        </div>
      </div>
      <div className="jh-panel__body">
        <div className="jh-fields">
          <dt>Site ID</dt>
          <dd><span className="jh-tag">{site.id || "—"}</span></dd>

          <dt>Origin</dt>
          <dd>{site.origin}</dd>

          <dt>Site URL</dt>
          <dd>
            <EditableSiteField
              value={site.siteUrl || site.url || ""}
              asLink
              onSave={(value) => window.JH_API.updateSite(siteRef, { url: value })}
            />
          </dd>

          <dt>Last reviewed</dt>
          <dd>{site.lastReviewed || "—"}</dd>

          <dt>Next review</dt>
          <dd>{site.nextReview || "—"}</dd>

          <dt>Interval</dt>
          <dd>{site.intervalDays} days</dd>

          <dt>State</dt>
          <dd>
            <select
              value={site.state}
              onChange={(e) => {
                const value = e.target.value;
                window.JH_API.updateSite(siteRef, { state: value })
                  .then(() => window.JH_TOAST.show(`State set to ${SITE_REVIEW_STATES.find(([state]) => state === value)?.[1] || "updated"}`))
                  .catch((error) => window.JH_TOAST.show(error.message, "error"));
              }}
            >
              {SITE_REVIEW_STATES.map(([value, label]) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </select>
          </dd>

          <dt>Added</dt>
          <dd>{site.addedAt ? site.addedAt.slice(0, 10) : "—"}</dd>

          <dt>Company name</dt>
          <dd>
            <EditableSiteField
              value={site.companyName || ""}
              onSave={(value) => window.JH_API.updateSite(siteRef, { company_name: value })}
            />
          </dd>

          <dt>Company website</dt>
          <dd>
            <EditableSiteField
              value={site.companyWebsite || ""}
              asLink
              onSave={(value) => window.JH_API.updateSite(siteRef, { company_website: value })}
            />
          </dd>

          <dt>Jobs URL</dt>
          <dd>
            <EditableSiteField
              value={site.jobsUrl || ""}
              asLink
              onSave={(value) => window.JH_API.updateSite(siteRef, { jobs_url: value })}
            />
          </dd>

          <dt>Company description</dt>
          <dd>
            <EditableSiteField
              value={site.companyDescription || ""}
              multiline
              onSave={(value) => window.JH_API.updateSite(siteRef, { company_description: value })}
            />
          </dd>

          <dt>Note</dt>
          <dd>
            <EditableSiteField
              value={site.note || ""}
              multiline
              onSave={(value) => window.JH_API.updateSite(siteRef, { note: value })}
            />
          </dd>
        </div>
      </div>
      {nextReviewDialog && (
        <AppTextInputDialog
          title="Set next review (days)"
          placeholder="14"
          defaultValue={String(site.intervalDays || 14)}
          onConfirm={(val) => {
            setNextReviewDialog(false);
            const days = Number(val) || 14;
            window.JH_API.updateSite(siteRef, { next_review_days: days })
              .then(() => window.JH_TOAST.show("Next review set"))
              .catch((e) => window.JH_TOAST.show(e.message, "error"));
          }}
          onClose={() => setNextReviewDialog(false)}
        />
      )}
      {intervalDialog && (
        <AppTextInputDialog
          title="Set review interval (days)"
          placeholder="14"
          defaultValue={String(site.intervalDays || 14)}
          onConfirm={(val) => {
            setIntervalDialog(false);
            const days = Number(val) || 14;
            window.JH_API.updateSite(siteRef, { interval_days: days })
              .then(() => window.JH_TOAST.show("Interval updated"))
              .catch((e) => window.JH_TOAST.show(e.message, "error"));
          }}
          onClose={() => setIntervalDialog(false)}
        />
      )}
      {noteDialog && (
        <AppTextInputDialog
          title="Site note"
          placeholder="Note about this site…"
          defaultValue={site.note || ""}
          onConfirm={(note) => {
            setNoteDialog(false);
            window.JH_API.updateSite(siteRef, { note })
              .then(() => window.JH_TOAST.show("Note saved"))
              .catch((e) => window.JH_TOAST.show(e.message, "error"));
          }}
          onClose={() => setNoteDialog(false)}
        />
      )}
    </div>
  );
}

function SitesPage({ selectedSiteId, onSelectSite, panelOpen }) {
  const [search, setSearch] = React.useState("");
  const [filter, setFilter] = React.useState("all"); // "due" | "never" | "all" | "recent"
  const [sites, setSites] = React.useState(() => window.JH_SITES || []);

  React.useEffect(() => {
    const refreshEvent = window.JH_SITE_UI_REFRESH_EVENT || "jobhunt:ui-data-refreshed";
    const refreshSites = () => setSites((window.JH_SITES || []).slice());
    refreshSites();
    window.addEventListener(refreshEvent, refreshSites);
    return () => window.removeEventListener(refreshEvent, refreshSites);
  }, []);

  const allSites = sites;
  const normalizedSelectedSiteId = selectedSiteId == null ? null : String(selectedSiteId);
  const selected = normalizedSelectedSiteId
    ? (sites.find((s) => String(s.id) === normalizedSelectedSiteId || s.origin === selectedSiteId) || null)
    : null;

  const filtered = allSites.filter(s => {
    if (filter === "due") {
      if (!s.nextReview || s.state === "exclude") return false;
      const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate() + 1); tomorrow.setHours(0, 0, 0, 0);
      if (new Date(s.nextReview) > tomorrow) return false;
    } else if (filter === "never") {
      if (s.state !== "not_reviewed") return false;
    } else if (filter === "recent") {
      if (s.state !== "reviewed") return false;
    }
    if (search) {
      const q = search.toLowerCase();
      return (
        s.origin.toLowerCase().includes(q) ||
        (s.companyName || "").toLowerCase().includes(q) ||
        (s.companyWebsite || "").toLowerCase().includes(q) ||
        (s.jobsUrl || "").toLowerCase().includes(q) ||
        (s.pageTitle || "").toLowerCase().includes(q) ||
        (s.note || "").toLowerCase().includes(q)
      );
    }
    return true;
  });

  function SiteRow({ s, isSelected, onSelectSite }) {
    const [nextReviewDialog, setNextReviewDialog] = React.useState(false);
    const [noteDialog, setNoteDialog] = React.useState(false);
    const siteRef = React.useMemo(() => s.id || s.origin, [s.id, s.origin]);

    const openUrl = React.useMemo(() => {
      if (s.openUrl) return s.openUrl;
      if (s.origin) {
        try {
          return new URL(s.origin).origin;
        } catch (e) {
          if (s.origin.startsWith("http://") || s.origin.startsWith("https://")) return s.origin;
        }
      }
      return s.siteUrl;
    }, [s.origin, s.openUrl, s.siteUrl]);

      return (
      <tr
        tabIndex={0}
        role="row"
        aria-selected={isSelected}
        data-selected={isSelected ? true : undefined}
        aria-current={isSelected ? "true" : undefined}
        onClick={() => onSelectSite(siteRef)}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onSelectSite(siteRef); } }}
      >
        <td>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
            <span style={{ width: 16, height: 16, borderRadius: 4, background: "var(--bg-elev-2)", border: "1px solid var(--border)", display: "inline-grid", placeItems: "center", fontSize: 9, fontFamily: "var(--font-mono)", color: "var(--fg-mute)" }}>
              {s.origin.slice(0, 1).toUpperCase()}
            </span>
            <span data-mono style={{ fontSize: 12 }}>{s.companyName || s.origin}</span>
            <Btn size="sm" kind="ghost" icon={<Icon.External size={11} />} title="Open" aria-label="Open site" onClick={(e) => { e.stopPropagation(); window.open(openUrl, "_blank"); }} />
          </span>
        </td>
        <td>
          {s.companyWebsite ? (
            <a href={s.companyWebsite} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>{s.companyWebsite}</a>
          ) : (
            <span style={{ color: "var(--fg-faint)" }}>—</span>
          )}
        </td>
        <td>
          {s.jobsUrl ? (
            <a href={s.jobsUrl} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>{s.jobsUrl}</a>
          ) : (
            <span style={{ color: "var(--fg-faint)" }}>—</span>
          )}
        </td>
        <td className="col-mono">{s.addedAt ? fmtDate(s.addedAt) : <span style={{ color: "var(--fg-faint)" }}>—</span>}</td>
        <td>
          <select
            value={s.state}
            onPointerDown={(e) => e.stopPropagation()}
            onMouseDown={(e) => e.stopPropagation()}
            onChange={(e) => {
              const value = e.target.value;
              if (!value) return;
              window.JH_API.updateSite(siteRef, { state: value })
                .then(() => window.JH_TOAST.show(`State set to ${SITE_REVIEW_STATES.find(([state]) => state === value)?.[1] || "updated"}`))
                .catch((error) => window.JH_TOAST.show(error.message, "error"));
            }}
            onClick={(e) => e.stopPropagation()}
            onKeyDown={(e) => e.stopPropagation()}
          >
            {SITE_REVIEW_STATES.map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </td>
        <td className="col-mono">{s.nextReview ? (
          <span className="jh-due" data-state={dueState(s.nextReview)}>
            <Icon.Calendar size={11} />
            {dueLabel(s.nextReview)}
          </span>
        ) : <span style={{ color: "var(--fg-faint)" }}>—</span>}
        </td>
        <td onClick={(e) => e.stopPropagation()}>
          <span className="row-actions">
            <Btn size="sm" kind="ghost" icon={<Icon.Check size={11} />} title="Mark reviewed today" aria-label="Mark reviewed today" onClick={() => window.JH_API.reviewSite(siteRef).catch((e) => window.JH_TOAST.show(e.message, "error"))} />
            <Btn size="sm" kind="ghost" icon={<Icon.Calendar size={11} />} title="Set next review" aria-label="Set next review" onClick={() => setNextReviewDialog(true)} />
            <Btn size="sm" kind="ghost" icon={<Icon.Note size={11} />} title="Add note" aria-label="Add note" onClick={() => setNoteDialog(true)} />
          </span>
          {nextReviewDialog && (
            <AppTextInputDialog
              title="Set next review (days)"
              placeholder="14"
              defaultValue={String(s.intervalDays || 14)}
              onConfirm={(val) => {
                setNextReviewDialog(false);
                const days = Number(val) || 14;
                window.JH_API.updateSite(siteRef, { next_review_days: days })
                  .then(() => window.JH_TOAST.show("Next review set"))
                  .catch((e) => window.JH_TOAST.show(e.message, "error"));
              }}
              onClose={() => setNextReviewDialog(false)}
            />
          )}
          {noteDialog && (
            <AppTextInputDialog
              title="Site note"
              placeholder="Note about this site…"
              defaultValue={s.note || ""}
              onConfirm={(note) => {
                setNoteDialog(false);
                window.JH_API.updateSite(siteRef, { note })
                  .then(() => window.JH_TOAST.show("Note saved"))
                  .catch((e) => window.JH_TOAST.show(e.message, "error"));
              }}
              onClose={() => setNoteDialog(false)}
            />
          )}
        </td>
      </tr>
    );
  }

  const filterLabels = { all: "All", due: "Due", never: "Not reviewed", recent: "Reviewed" };

  return (
    <>
      <div className="jh-toolbar">
        <div className="jh-search">
          <Icon.Search size={13} className="ico" />
          <input
            placeholder="Search sites…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          {search && <span className="kbd" style={{ cursor: "pointer" }} onClick={() => setSearch("")}>✕</span>}
        </div>
        <div style={{ display: "flex", gap: 4 }}>
          {Object.entries(filterLabels).map(([key, label]) => (
            <Btn key={key} size="sm" kind={filter === key ? "accent" : "ghost"} onClick={() => setFilter(key)}>{label}</Btn>
          ))}
        </div>
      </div>

      <div className="jh-tablewrap">
        {filtered.length === 0 ? (
          <div style={{ padding: "48px 24px", textAlign: "center", color: "var(--fg-mute)" }}>
            {allSites.length === 0 ? "No sites tracked yet. Visit a job board and use the Chrome extension (or POST to /site-reviews) to mark it reviewed." : "No sites match the current filter."}
          </div>
        ) : (
              <table className="jh-table" style={{ tableLayout: "fixed" }}>
            <colgroup>
              <col style={{ width: 260 }} />
              <col style={{ width: 170 }} />
              <col style={{ width: 220 }} />
              <col style={{ width: 110 }} />
              <col style={{ width: 130 }} />
              <col style={{ width: 100 }} />
              <col style={{ width: panelOpen ? 60 : 200 }} />
            </colgroup>
            <thead>
              <tr>
                <th>Company</th>
                <th>Company website</th>
                <th>Jobs URL</th>
                <th>Added</th>
                <th>State</th>
                <th>Next review</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((s) => {
                const siteRef = s.id || s.origin;
                const isSelected = selectedSiteId == null
                  ? false
                  : String(selectedSiteId) === String(siteRef) || String(selected?.id) === String(s.id) || selected?.origin === s.origin;
                return (
                  <SiteRow
                    key={siteRef}
                    s={s}
                    isSelected={isSelected}
                    onSelectSite={onSelectSite}
                  />
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}

Object.assign(window, { SitesPage, SiteDetail });
