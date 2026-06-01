// Jobhunt — top-level App, used inside each design-canvas artboard.

const VALID_ROUTES = ["dashboard", "jobs", "quality", "needs", "sites", "duplicates", "settings", "llm-queue"];

function parseHash() {
  const raw = window.location.hash.replace(/^#\//, "");
  const [path, query = ""] = raw.split("?");
  const hash = path.split("/");
  const section = hash[0] || "jobs";
  const params = new URLSearchParams(query);
  const itemRef = hash[1] ? decodeURIComponent(hash[1]) : null;
  return {
    route: VALID_ROUTES.includes(section) ? section : "jobs",
    itemRef,
    view: params.get("view") || null,
    issue: params.get("issue") || null,
  };
}

function resolveJobRef(jobRef) {
  if (!jobRef) return null;
  const num = parseInt(jobRef);
  const job = (window.JH_JOBS || []).find(j => j.jobNumber === num);
  return job?.id || null;
}

function resolveSiteRef(siteRef) {
  if (!siteRef) return null;
  const site = (window.JH_SITES || []).find(s => String(s.id) === String(siteRef) || s.origin === siteRef);
  return site ? (site.id || site.origin) : null;
}

function JobhuntApp({ initialRoute = "jobs", initialJobId = null, initialTheme = "auto", initialTab = "overview", panelOpen: panelOpenProp = null }) {
  const initial = parseHash();
  // If the hash has a route, use it; otherwise fall back to prop
  const hasHash = window.location.hash.length > 1;
  const startRoute = hasHash ? initial.route : initialRoute;
  const startJobId = hasHash && initial.route === "jobs" ? resolveJobRef(initial.itemRef) : initialJobId;
  const startSiteId = hasHash && initial.route === "sites" ? resolveSiteRef(initial.itemRef) : null;
  const startSavedView = hasHash && initial.route === "jobs" ? initial.view : null;
  const startQualityIssue = hasHash && initial.route === "quality" ? initial.issue : null;

  const [route, setRoute] = React.useState(startRoute);
  const [themeMode, setThemeMode] = React.useState(() => localStorage.getItem("jobhunt.theme") || initialTheme);
  const [systemDark, setSystemDark] = React.useState(() => window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
  const [selectedJobId, setSelectedJobId] = React.useState(startJobId);
  const [selectedSiteId, setSelectedSiteId] = React.useState(startSiteId);
  const [savedViewName, setSavedViewName] = React.useState(startSavedView);
  const [qualityIssue, setQualityIssue] = React.useState(startQualityIssue);
  const [notFound, setNotFound] = React.useState(() => {
    if (hasHash && initial.route === "jobs" && initial.itemRef && !resolveJobRef(initial.itemRef)) return initial.itemRef;
    return null;
  });
  const [detailTab, setDetailTab] = React.useState(initialTab);
  const [, setDataVersion] = React.useState(0);
  React.useEffect(() => {
    localStorage.setItem("jobhunt.theme", themeMode);
  }, [themeMode]);
  React.useEffect(() => {
    const bump = () => setDataVersion(v => v + 1);
    const uiRefreshEvent = window.JH_SITE_UI_REFRESH_EVENT || "jobhunt:ui-data-refreshed";
    const queueRefreshEvent = window.JH_LLM_QUEUE_REFRESH_EVENT || "jobhunt:llm-queue-refreshed";
    window.addEventListener(uiRefreshEvent, bump);
    window.addEventListener(queueRefreshEvent, bump);
    return () => {
      window.removeEventListener(uiRefreshEvent, bump);
      window.removeEventListener(queueRefreshEvent, bump);
    };
  }, []);
  React.useEffect(() => {
    if (!window.matchMedia) return;
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const update = () => setSystemDark(media.matches);
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);
  const theme = themeMode === "auto" ? (systemDark ? "dark" : "light") : themeMode;

  // Push hash on route/right-panel changes
  function pushHash(newRoute, newJobId, newSiteId, newSavedViewName, newQualityIssue) {
    let hash = `#/${newRoute}`;
    const params = new URLSearchParams();
    if (newRoute === "jobs" && newJobId) {
      const job = (window.JH_JOBS || []).find(j => j.id === newJobId);
      if (job?.jobNumber) hash += `/${job.jobNumber}`;
    } else if (newRoute === "sites" && newSiteId) {
      const site = (window.JH_SITES || []).find(s => String(s.id) === String(newSiteId) || s.origin === newSiteId);
      const siteRef = site ? (site.id || site.origin) : newSiteId;
      hash += `/${encodeURIComponent(siteRef)}`;
    }
    if (newRoute === "jobs" && newSavedViewName) {
      params.set("view", newSavedViewName);
    } else if (newRoute === "quality" && newQualityIssue && newQualityIssue !== "all") {
      params.set("issue", newQualityIssue);
    }
    if ([...params].length) {
      hash += `?${params.toString()}`;
    }
    if (window.location.hash !== hash) {
      window.history.pushState(null, "", hash);
    }
  }

  // Sync hash when route/right-panel selection changes
  React.useEffect(() => {
    pushHash(route, selectedJobId, selectedSiteId, savedViewName, qualityIssue);
  }, [route, selectedJobId, selectedSiteId, savedViewName, qualityIssue]);

  // Handle browser back/forward
  React.useEffect(() => {
    const handler = () => {
      const parsed = parseHash();
      setRoute(parsed.route);
      if (parsed.route === "jobs" && parsed.itemRef) {
        const resolved = resolveJobRef(parsed.itemRef);
        setSelectedJobId(resolved);
        setSelectedSiteId(null);
        setSavedViewName(parsed.view);
        setQualityIssue(null);
        setNotFound(resolved ? null : parsed.itemRef);
      } else if (parsed.route === "jobs") {
        setSelectedJobId(null);
        setSelectedSiteId(null);
        setSavedViewName(parsed.view);
        setQualityIssue(null);
        setNotFound(null);
      } else if (parsed.route === "quality") {
        setSelectedJobId(null);
        setSelectedSiteId(null);
        setSavedViewName(null);
        setQualityIssue(parsed.issue);
        setNotFound(null);
      } else if (parsed.route === "sites" && parsed.itemRef) {
        setSelectedJobId(null);
        setSelectedSiteId(resolveSiteRef(parsed.itemRef));
        setSavedViewName(null);
        setQualityIssue(null);
        setNotFound(null);
      } else {
        setSelectedJobId(null);
        setSelectedSiteId(null);
        setSavedViewName(null);
        setQualityIssue(null);
        setNotFound(null);
      }
    };
    window.addEventListener("popstate", handler);
    return () => window.removeEventListener("popstate", handler);
  }, []);

  // Global Cmd+K: navigate to jobs and focus search from anywhere
  React.useEffect(() => {
    const handler = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        if (route !== "jobs") setRoute("jobs");
        // Give React a tick to mount JobsPage if we just navigated
        setTimeout(() => window.JH_FOCUS_JOBS_SEARCH?.(), 30);
      }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [route]);

  // panelOpenProp is sticky override: if a parent forces open or closed.
  const panelOpen = panelOpenProp != null ? panelOpenProp : (route === "jobs" && selectedJobId != null) || (route === "sites" && selectedSiteId != null);

  function navigate(newRoute) {
    setRoute(newRoute);
    if (newRoute !== "jobs") setSelectedJobId(null);
    if (newRoute !== "jobs") setSavedViewName(null);
    if (newRoute !== "sites") setSelectedSiteId(null);
    if (newRoute !== "quality") setQualityIssue(null);
  }

  function selectJob(id) {
    setSelectedJobId(id);
    setNotFound(null);
    if (route !== "jobs") setRoute("jobs");
  }
  function selectJobs(ids) {
    window.JH_PENDING_SELECTED_JOB_IDS = ids;
    setSelectedJobId(null);
    setSavedViewName(null);
    setQualityIssue(null);
    setNotFound(null);
    setRoute("jobs");
    setTimeout(() => window.dispatchEvent(new Event("jobhunt:select-jobs")), 30);
  }
  function selectSite(siteId) { setSelectedSiteId(siteId); if (route !== "sites") setRoute("sites"); }
  function closeDetail() { setSelectedJobId(null); }
  function closeSiteDetail() { setSelectedSiteId(null); }
  const [processingExtractions, setProcessingExtractions] = React.useState(false);
  const [selCount, setSelCount] = React.useState(0);
  React.useEffect(() => { window.JH_SET_SEL_COUNT = setSelCount; return () => { delete window.JH_SET_SEL_COUNT; }; }, []);

  function processPendingExtractions() {
    if (processingExtractions) return;
    setProcessingExtractions(true);
    const selected = window.JH_SELECTED_JOB_IDS || [];
    if (selected.length > 0) {
      // Requeue only the selected jobs, then process exactly those request IDs
      window.JH_TOAST?.show(`${selected.length} job${selected.length !== 1 ? "s" : ""} queued for AI reprocessing`, "info");
      Promise.all(selected.map((id) => window.JH_API.api(`/api/jobs/${id}/extract`, { method: "POST" })))
        .then((results) => {
          const requestIds = results.map(r => r.request_id).filter(Boolean);
          return window.JH_API.api("/api/llm-queue/process-selected", {
            method: "POST",
            body: JSON.stringify({ request_ids: requestIds }),
          });
        })
        .then(() => window.JH_REFRESH_UI_DATA?.())
        .catch((err) => window.JH_TOAST?.show("Extraction failed: " + (err.message || err), "error"))
        .finally(() => setProcessingExtractions(false));
    } else {
      window.JH_TOAST?.show("Extraction running in background", "info");
      window.JH_API.processExtractions()
        .then(() => window.JH_REFRESH_UI_DATA?.())
        .catch((err) => window.JH_TOAST?.show("Extraction failed: " + (err.message || err), "error"))
        .finally(() => setProcessingExtractions(false));
    }
  }

  return (
    <div className="jh-root" data-theme={theme}>
      <ToastContainer />
      <div className={`jh-shell ${panelOpen ? "jh-shell--with-panel" : ""}`}>
        <Sidebar route={route} setRoute={navigate} setSavedViewName={setSavedViewName} theme={theme} themeMode={themeMode} onToggleTheme={() => setThemeMode((t) => t === "dark" ? "light" : t === "light" ? "auto" : "dark")} />

        <main className="jh-main">
          <TopBar
            route={route}
            right={<RouteActions route={route} onProcessExtractions={processPendingExtractions} processingExtractions={processingExtractions} selCount={selCount} />}
          >
            {route === "jobs" && selectedJobId && (
              <>
                <span className="sep">/</span>
                <span style={{ color: "var(--fg-mute)" }}>
                  {window.JH_JOBS.find((j) => j.id === selectedJobId)?.company}
                </span>
              </>
            )}
          </TopBar>

          {notFound && !panelOpen && (
            <div className="jh-not-found">
              Job #{notFound} not found · <button onClick={() => setNotFound(null)}>dismiss</button>
            </div>
          )}

          {route === "dashboard" && <DashboardPage onSelectJob={selectJob} onProcessExtractions={processPendingExtractions} processingExtractions={processingExtractions} />}
          {route === "jobs" && <JobsPage selectedJobId={selectedJobId} onSelectJob={selectJob} panelOpen={panelOpen} savedViewName={savedViewName} setSavedViewName={setSavedViewName} />}
          {route === "quality" && <DataQualityPage onSelectJob={selectJob} onSelectJobs={selectJobs} issue={qualityIssue} setIssue={setQualityIssue} />}
          {route === "needs" && <NeedsActionPage onSelectJob={selectJob} />}
          {route === "sites" && <SitesPage selectedSiteId={selectedSiteId} onSelectSite={selectSite} panelOpen={panelOpen} />}
        {route === "duplicates" && <DuplicatesPage mode={panelOpenProp === "compare" ? "compare" : "list"} />}
        {route === "settings" && <SettingsPage />}
        {route === "llm-queue" && <LlmQueuePage />}
      </main>

        {panelOpen && route === "jobs" && (
          <JobDetail
            jobId={selectedJobId}
            onClose={closeDetail}
            initialTab={detailTab}
            key={selectedJobId + ":" + detailTab}
            jobIds={window.JH_JOBS.map(j => j.id)}
            onNavigate={setSelectedJobId}
          />
        )}

        {panelOpen && route === "sites" && (
          <SiteDetail
            siteId={selectedSiteId}
            onClose={closeSiteDetail}
          />
        )}
      </div>
    </div>
  );
}

function RouteActions({ route, onProcessExtractions, processingExtractions, selCount = 0 }) {
  const [addSiteDialog, setAddSiteDialog] = React.useState(null); // null | "url" | "note"
  const [pendingSiteUrl, setPendingSiteUrl] = React.useState("");
  const [checkingAvailability, setCheckingAvailability] = React.useState(false);

  function checkAvailability() {
    if (checkingAvailability) return;
    setCheckingAvailability(true);
    window.JH_TOAST?.show("Checking job availability…", "info");
    window.JH_API.checkAvailability()
      .then((res) => {
        const msg = res.marked > 0
          ? `${res.marked} job${res.marked !== 1 ? "s" : ""} marked as not available (${res.checked} checked)`
          : `All ${res.checked} jobs still available`;
        window.JH_TOAST?.show(msg, res.marked > 0 ? "warn" : "info");
        if (res.marked > 0) window.JH_REFRESH_UI_DATA?.();
      })
      .catch((err) => window.JH_TOAST?.show("Availability check failed: " + (err.message || err), "error"))
      .finally(() => setCheckingAvailability(false));
  }

  if (route === "jobs") {
    const processLabel = processingExtractions ? "Running…" : selCount > 0 ? `Run AI extraction (${selCount})` : "Run AI extraction";
    return (
      <>
        <Btn size="sm" kind="accent" icon={<Icon.Sparkles size={12} />} onClick={onProcessExtractions} disabled={processingExtractions}>{processLabel}</Btn>
        <Btn size="sm" kind="ghost" icon={<Icon.Search size={12} />} onClick={checkAvailability} disabled={checkingAvailability} title="Check all active jobs for availability">Check availability</Btn>
        <Btn size="sm" kind="ghost" icon={<Icon.Refresh size={12} />} onClick={() => window.location.reload()}>Reload</Btn>
        <Btn size="sm" icon={<Icon.External size={12} />} onClick={() => window.open("/exports/jobs.csv", "_blank")}>Export</Btn>
      </>
    );
  }
  if (route === "dashboard") {
    const processLabel = processingExtractions ? "Running…" : selCount > 0 ? `Run AI extraction (${selCount})` : "Run AI extraction";
    return <Btn size="sm" kind="accent" icon={<Icon.Sparkles size={12} />} onClick={onProcessExtractions} disabled={processingExtractions}>{processLabel}</Btn>;
  }
  if (route === "needs") {
    return (
      <>
        <Btn size="sm" kind="ghost" icon={<Icon.Calendar size={12} />} disabled>Snooze all</Btn>
      </>
    );
  }
  if (route === "sites") {
    return (
      <>
        <Btn size="sm" kind="accent" icon={<Icon.Plus size={12} />} onClick={() => setAddSiteDialog("url")}>Add site</Btn>
        {addSiteDialog === "url" && (
          <AppTextInputDialog
            title="Add site"
            placeholder="https://jobs.example.com"
            onConfirm={(url) => { setPendingSiteUrl(url); setAddSiteDialog("note"); }}
            onClose={() => setAddSiteDialog(null)}
          />
        )}
        {addSiteDialog === "note" && (
          <AppTextInputDialog
            title="Add note (optional)"
            placeholder="e.g. Check weekly for new roles"
            defaultValue=""
            onConfirm={(note) => {
              setAddSiteDialog(null);
              const siteUrl = pendingSiteUrl;
              window.JH_API.addSite({
                url: siteUrl,
                origin: (() => { try { return new URL(siteUrl).origin; } catch { return siteUrl; } })(),
                page_title: "",
                interval_days: (window.JH_SETTINGS.site_review_interval_days) || 14,
                note,
              }).catch((e) => window.JH_TOAST.show(e.message, "error"));
            }}
            onClose={() => { setAddSiteDialog("url"); }}
          />
        )}
      </>
    );
  }
  if (route === "duplicates") {
    return (
      <>
        <Btn size="sm" icon={<Icon.Refresh size={12} />} onClick={() => window.location.reload()}>Rescan</Btn>
      </>
    );
  }
  if (route === "settings") {
    return null;
  }
  if (route === "llm-queue") {
    return null;
  }
  return <Btn size="sm" kind="accent" icon={<Icon.Plus size={12} />} disabled>Capture URL</Btn>;
}


Object.assign(window, { JobhuntApp });
