// Fetches real data from the local API and mounts the app.
(async function () {
  const STATUSES = ["saved", "applied", "interview", "offer", "rejected", "archived", "not_available", "duplicate"];
  const rootEl = document.getElementById("root");
  const savedTheme = localStorage.getItem("jobhunt.theme");
  const prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  const resolvedTheme = savedTheme === "light" ? "light" : savedTheme === "dark" ? "dark" : prefersDark ? "dark" : "light";
  const initialTheme = savedTheme || "auto";

  function mapStatus(dbStatus) {
    const map = {
      saved: "saved",
      interested: "saved",
      applied: "applied",
      interviewing: "interview",
      offer: "offer",
      rejected: "rejected",
      closed: "archived",
      ignored: "archived",
      duplicate: "duplicate",
    };
    return map[dbStatus] || dbStatus;
  }

  function mapRemote(remoteType) {
    if (!remoteType) return "—";
    const map = { remote: "Remote", hybrid: "Hybrid", onsite: "Onsite", unknown: "—" };
    return map[remoteType] || remoteType;
  }

  function mapEmployment(raw) {
    if (!raw) return "—";
    const map = {
      full_time: "Full-time",
      fulltime: "Full-time",
      "full-time": "Full-time",
      part_time: "Part-time",
      parttime: "Part-time",
      "part-time": "Part-time",
      contract: "Contract",
      contractor: "Contract",
      freelance: "Freelance",
      internship: "Internship",
      intern: "Internship",
      temporary: "Temporary",
      temp: "Temporary",
    };
    const key = raw.toLowerCase().replace(/\s+/g, "_");
    return map[key] || map[raw.toLowerCase()] || (raw.charAt(0).toUpperCase() + raw.slice(1));
  }

  const STATE_ABBREV_TO_NAME = { wa: "washington" };
  const STATE_NAME_TO_ABBREV = { washington: "wa" };

  function normalizeForMatch(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  }

  function parsePreferredLocations(value) {
    const terms = [];
    const seen = new Set();
    for (const raw of String(value || "").split(",")) {
      const token = raw.trim();
      if (!token) continue;
      const base = token.toLowerCase();
      if (!seen.has(base)) { terms.push(token); seen.add(base); }
      if (STATE_ABBREV_TO_NAME[base] && !seen.has(STATE_ABBREV_TO_NAME[base])) {
        terms.push(STATE_ABBREV_TO_NAME[base]);
        seen.add(STATE_ABBREV_TO_NAME[base]);
      }
      if (STATE_NAME_TO_ABBREV[base] && !seen.has(STATE_NAME_TO_ABBREV[base])) {
        terms.push(STATE_NAME_TO_ABBREV[base]);
        seen.add(STATE_NAME_TO_ABBREV[base]);
      }
    }
    return terms;
  }

  function matchesLocation(location, terms) {
    const haystack = normalizeForMatch(location);
    return terms.some(term => {
      const needle = normalizeForMatch(term);
      if (!needle) return false;
      if (needle.length === 2) return new RegExp(`\\b${needle}\\b`).test(haystack);
      return haystack.includes(needle);
    });
  }

  function meetsLocationCriteria(job, settings) {
    const remoteType = job.remote_type || "unknown";
    const terms = parsePreferredLocations(settings.preferred_locations);
    const allowRemote = parseSettingBool(settings.location_allow_remote, true);
    const allowHybrid = parseSettingBool(settings.location_allow_hybrid, true);
    const allowOnsite = parseSettingBool(settings.location_allow_onsite, true);
    if (!terms.length) {
      if (remoteType === "remote") return allowRemote;
      if (remoteType === "hybrid") return allowHybrid;
      if (remoteType === "onsite") return allowOnsite;
      return allowOnsite;
    }
    if (remoteType === "remote") return allowRemote;
    const locationMatches = matchesLocation(job.location, terms);
    if (remoteType === "hybrid") return allowHybrid && locationMatches;
    if (remoteType === "onsite") return allowOnsite && locationMatches;
    return allowOnsite && locationMatches;
  }

  function sourceTextIndicatesRemote(text) {
    return /\b(remote|hybrid|work from home|telecommute|hiring remotely|days?\s*\/\s*week\s+in-office)\b/i.test(String(text || ""));
  }

  function sourceTextIndicatesLocation(text) {
    return /\b(Location|United States|Remote|[A-Z][a-z]+,\s*[A-Z]{2})\b/.test(String(text || ""));
  }

  function fieldSource({ field, job, extracted, manualOverrides, settings }) {
    if (manualOverrides.has(field)) return "manual override";
    if (field === "meetsCriteria") return typeof extracted?.meets_criteria === "boolean" ? "LLM" : "app location filter";
    if (field === "salary") {
      if (extracted?.salary_min || extracted?.salary_max || extracted?.salary_note) return "LLM";
      if (job.structured_data_count > 0) return "structured data";
      return "not set";
    }
    if (field === "location") {
      if (extracted?.location) return "LLM";
      if (sourceTextIndicatesLocation(job.raw_text)) return "source fallback";
      return "not set";
    }
    if (field === "workMode") {
      if (extracted?.remote_type && extracted.remote_type !== "unknown") return "LLM";
      if (sourceTextIndicatesRemote(job.raw_text) || sourceTextIndicatesRemote(job.source_url)) return "source fallback";
      return "not set";
    }
    return settings ? "app" : "unknown";
  }

  const FALSE_VALUES = new Set(["0", "false", "no", "off", "disabled"]);
  function parseSettingBool(value, fallback = true) {
    if (typeof value === "boolean") return value;
    if (value == null) return fallback;
    const normalized = String(value).trim().toLowerCase();
    if (normalized === "1" || normalized === "true" || normalized === "yes" || normalized === "on" || normalized === "enabled") {
      return true;
    }
    if (FALSE_VALUES.has(normalized)) {
      return false;
    }
    return fallback;
  }

  function FirstRunSetupDialog({ initialSettings, onComplete }) {
    const [preferredLocations, setPreferredLocations] = React.useState(initialSettings.preferred_locations || "");
    const [allowRemote, setAllowRemote] = React.useState(parseSettingBool(initialSettings.location_allow_remote, true));
    const [allowHybrid, setAllowHybrid] = React.useState(parseSettingBool(initialSettings.location_allow_hybrid, true));
    const [allowOnsite, setAllowOnsite] = React.useState(parseSettingBool(initialSettings.location_allow_onsite, true));
    const [saving, setSaving] = React.useState(false);
    const [error, setError] = React.useState(null);
    const canSave = allowRemote || allowHybrid || allowOnsite;

    async function handleSave() {
      if (!canSave) return;
      setSaving(true);
      setError(null);
      try {
        const payload = {
          preferred_locations: preferredLocations.trim(),
          location_allow_remote: allowRemote,
          location_allow_hybrid: allowHybrid,
          location_allow_onsite: allowOnsite,
        };
        await window.JH_API.saveSettings(payload);
        Object.assign(window.JH_SETTINGS, payload);
        localStorage.setItem("jobhunt.first_run_complete", "1");
        localStorage.removeItem("jobhunt.force_first_run");
        onComplete();
      } catch (e) {
        setError(e.message || String(e));
      } finally {
        setSaving(false);
      }
    }

    function handleSkip() {
      localStorage.setItem("jobhunt.first_run_complete", "1");
      localStorage.removeItem("jobhunt.force_first_run");
      onComplete();
    }

    return (
      <AppDialog
        title="Welcome to Jobhunt"
        onClose={handleSkip}
        actions={[
          { label: "Skip for now", kind: "ghost", onClick: handleSkip },
          { label: "Save preferences", kind: "accent", onClick: handleSave, disabled: !canSave || saving },
        ]}
      >
        <p style={{ marginTop: 0, color: "var(--fg-mute)" }}>
          Tell Jobhunt where you're willing to work so it can flag matching jobs. The Help page in the left sidebar has the full capture, extraction, and review workflow.
        </p>
        <div style={{ marginTop: 12 }}>
          <div className="jh-label">States you'd work in</div>
          <div className="jh-input">
            <input
              value={preferredLocations}
              onChange={(e) => setPreferredLocations(e.target.value)}
              placeholder="e.g. WA, TX, NY"
              autoFocus
            />
          </div>
          <div style={{ fontSize: 11, color: "var(--fg-mute)", marginTop: 4 }}>
            Enter state abbreviations — a state match covers all cities in that state. Add specific cities if you want to narrow further (WA, Seattle).
          </div>
        </div>
        <div style={{ marginTop: 14 }}>
          <div className="jh-label" style={{ marginBottom: 6 }}>Work arrangements you'd consider</div>
          <div className="jh-row" style={{ gap: 16, alignItems: "center", flexWrap: "wrap" }}>
            <label className="jh-label" style={{ width: "auto", margin: 0 }}>
              <input type="checkbox" checked={allowRemote} onChange={(e) => setAllowRemote(e.target.checked)} />
              Remote
            </label>
            <label className="jh-label" style={{ width: "auto", margin: 0 }}>
              <input type="checkbox" checked={allowHybrid} onChange={(e) => setAllowHybrid(e.target.checked)} />
              Hybrid
            </label>
            <label className="jh-label" style={{ width: "auto", margin: 0 }}>
              <input type="checkbox" checked={allowOnsite} onChange={(e) => setAllowOnsite(e.target.checked)} />
              In-office
            </label>
          </div>
        </div>
        {error && (
          <div style={{ marginTop: 10, color: "var(--st-rejected)", fontSize: 12 }}>
            {error}
          </div>
        )}
        {!canSave && (
          <div style={{ marginTop: 8, fontSize: 11, color: "var(--fg-mute)" }}>
            Select at least one work arrangement to continue.
          </div>
        )}
      </AppDialog>
    );
  }

  function JobhuntFirstRunBootstrap({ shouldShow, initialTheme = "auto" }) {
    const [showSetup, setShowSetup] = React.useState(shouldShow);

    return (
      <>
        <JobhuntApp initialRoute="jobs" initialTheme={initialTheme} />
        {showSetup && <FirstRunSetupDialog initialSettings={window.JH_SETTINGS} onComplete={() => setShowSetup(false)} />}
      </>
    );
  }

  function mapExtractionStatus(s) {
    if (s === "succeeded") return "ok";
    if (s === "failed") return "fail";
    return "pending";
  }

  function urlToSource(url) {
    try {
      return new URL(url).hostname.replace("www.", "").replace("jobs.", "").replace("boards.", "").replace("apply.", "");
    } catch { return url; }
  }

  async function api(path, options = {}) {
    const res = await fetch(path, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...(options.headers || {}),
      },
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(text || `${res.status} ${res.statusText}`);
    }
    return res.json();
  }

  async function mutate(path, options = {}) {
    await api(path, options);
    await refreshUiDataOrReload();
  }

  const UI_DATA_REFRESH_EVENT = "jobhunt:ui-data-refreshed";

  function normalizeSiteState(rawSite) {
    const normalized = String(rawSite.state || "").toLowerCase().replace("-", "_");
    if (normalized === "not_reviewed" || normalized === "reviewed" || normalized === "exclude") {
      return normalized;
    }
    if (!rawSite.last_reviewed_at) return "not_reviewed";
    if (rawSite.state === "exclude") return "exclude";
    return "reviewed";
  }

  function mapUiData(raw) {
    const jobs = (raw.jobs || []).map(j => {
      let extracted = null;
      try {
        extracted = j.extracted_json
          ? (typeof j.extracted_json === "string" ? JSON.parse(j.extracted_json) : j.extracted_json)
          : null;
      } catch (e) {
        console.warn(`Failed to parse extracted_json for job ${j.job_id}:`, e);
      }
      let manualOverrides = [];
      try {
        manualOverrides = j.manual_overrides
          ? (typeof j.manual_overrides === "string" ? JSON.parse(j.manual_overrides) : j.manual_overrides)
          : [];
      } catch (_e) {
        manualOverrides = [];
      }
      const manualOverrideSet = new Set(Array.isArray(manualOverrides) ? manualOverrides : []);
      const provenanceInput = { job: j, extracted, manualOverrides: manualOverrideSet, settings: raw.settings || {} };
      return {
        id: j.job_id,
        jobNumber: j.job_number,
        status: mapStatus(j.status),
        company: j.company || "Unknown",
        title: j.title || j.page_title || "Unknown",
        location: (!j.location || j.location.toLowerCase() === "unknown") ? "—" : j.location,
        remote: (typeof extracted?.meets_criteria === "boolean" ? extracted.meets_criteria : meetsLocationCriteria(j, raw.settings || {})) ? "Yes" : "No",
        workMode: mapRemote(j.remote_type),
        salaryMin: j.salary_min || null,
        salaryMax: j.salary_max || null,
        currency: j.salary_currency || null,
        salaryNote: j.salary_note || extracted?.salary_note || null,
        employment: mapEmployment(extracted?.employment_type),
        seniority: extracted?.seniority || null,
        source: urlToSource(j.source_url),
        sourceUrl: j.source_url,
        capturedAt: j.captured_at,
        lastOpenedAt: j.last_opened_at || null,
        unread: !!j.unread,
        extraction: {
          status: mapExtractionStatus(j.extraction_status),
          at: j.extracted_at || null,
          model: j.extraction_model || null,
          error: j.extraction_error || null,
          confidence: j.extraction_confidence != null ? j.extraction_confidence : null,
          fieldConfidence: extracted?.confidence || {},
        },
        fieldProvenance: {
          location: fieldSource({ ...provenanceInput, field: "location" }),
          salary: fieldSource({ ...provenanceInput, field: "salary" }),
          workMode: fieldSource({ ...provenanceInput, field: "workMode" }),
          meetsCriteria: fieldSource({ ...provenanceInput, field: "meetsCriteria" }),
        },
        applicationUrl: j.application_url || null,
        fit: {
          score: (j.fit_score != null ? j.fit_score : null),
          status: j.fit_status || "none",
          dimensions: j.fit_score_json?.dimensions || [],
          summary: j.fit_score_json?.summary || null,
          requirements_met: j.fit_score_json?.requirements_met || [],
          requirements_not_met: j.fit_score_json?.requirements_not_met || [],
          model: j.fit_score_json?.model || null,
          scoredAt: j.fit_score_json?.scored_at || null,
          error: j.fit_score_json?.error || null,
        },
        nextAction: j.next_action ? {
          id: j.next_action.id,
          note: j.next_action.note,
          dueDate: j.next_action.due_date,
          snoozedUntil: j.next_action.snoozed_until || null,
        } : null,
        skills: extracted?.skills || [],
        summary: extracted?.summary || null,
        requirements: extracted?.requirements || [],
        niceToHaves: extracted?.nice_to_haves || [],
        benefits: extracted?.benefits || [],
        rating: j.rating || null,
        hasDuplicate: !!j.duplicate_of_job_id,
        duplicateOfJobId: j.duplicate_of_job_id || null,
        cleanedHash: j.cleaned_hash || null,
        rawHash: j.raw_hash || null,
        rawByteSize: j.raw_byte_size || 0,
        visibleByteSize: j.visible_byte_size || 0,
        cleanedByteSize: j.cleaned_byte_size || 0,
        selectedTextPresent: !!j.selected_text_present,
        structuredDataCount: j.structured_data_count || 0,
        cleanedDescription: j.cleaned_description || "",
        canonicalUrl: j.canonical_url || null,
        dataQualityReviewedAt: j.data_quality_reviewed_at || null,
        events: (j.events || []).map(e => ({
          kind: e.event_type === "captured" ? "capture"
            : e.event_type === "recaptured" ? "recapture"
            : e.event_type === "status_changed" ? "status"
            : e.event_type === "note_added" ? "note"
            : e.event_type === "applied" ? "applied"
            : e.event_type === "interview_scheduled" ? "interview"
            : e.event_type === "offer_received" ? "offer"
            : e.event_type === "rejected" ? "rejected"
            : e.event_type,
          at: e.occurred_at,
          note: e.note || undefined,
          body: e.event_type === "note_added" ? e.note : undefined,
        })),
        lastStatusChangedAt: (j.events || [])
          .filter(e => e.event_type === "status_changed")
          .map(e => e.occurred_at)
          .sort()
          .at(-1) || null,
        raw: j.raw_text || "",
      };
    });

    const companies = {};
    jobs.forEach(j => {
      if (j.company && !companies[j.company]) {
        companies[j.company] = {
          mono: j.company.split(/\s+/).map(w => w[0]).join("").slice(0, 2).toUpperCase(),
          origin: urlToSource(j.sourceUrl),
        };
      }
    });

    const sites = (raw.sites || []).map(s => ({
      id: s.id,
      siteUrl: s.url,
      origin: s.origin,
      pageTitle: s.page_title || s.origin,
      companyName: s.company_name || "",
      companyWebsite: s.company_website || "",
      jobsUrl: s.jobs_url || "",
      companyDescription: s.company_description || "",
      intervalDays: s.interval_days || 14,
      lastReviewed: s.last_reviewed_at ? s.last_reviewed_at.slice(0, 10) : null,
      nextReview: s.next_review_at ? s.next_review_at.slice(0, 10) : null,
      note: s.note || "",
      addedAt: s.added_at || null,
      state: normalizeSiteState(s),
      nextReviewState: (() => {
        if (!s.next_review_at || !s.last_reviewed_at) return "never";
        const days = Math.round((new Date(s.next_review_at) - new Date()) / 86400000);
        if (days < 0) return "overdue";
        if (days === 0) return "today";
        if (days <= 3) return "soon";
        return "future";
      })(),
    }));

    const dupes = (raw.dupes || []).map(g => ({
      id: g.group_id,
      kind: g.kind || "exact_hash",
      cleanedHash: g.cleaned_hash,
      hash: g.cleaned_hash ? g.cleaned_hash.slice(0, 8) + "…" : (g.group_id || "—"),
      similarity: Number(g.similarity ?? 1.0),
      reason: g.reason || "Identical cleaned description hash",
      jobIds: g.job_ids,
    }));

    const counts = { saved: 0, applied: 0, interview: 0, offers: 0, rejected: 0, archived: 0, duplicates: 0, pendingExtraction: 0, failedExtraction: 0 };
    jobs.forEach(j => {
      if (j.status === "saved") counts.saved++;
      else if (j.status === "applied") counts.applied++;
      else if (j.status === "interview") counts.interview++;
      else if (j.status === "offer") counts.offers++;
      else if (j.status === "rejected") counts.rejected++;
      else if (j.status === "archived") counts.archived++;
      else if (j.status === "duplicate") counts.duplicates++;
      if (j.extraction.status === "pending") counts.pendingExtraction++;
      if (j.extraction.status === "fail") counts.failedExtraction++;
    });

    const metrics = {
      ...counts,
      ...(raw.metrics || {}),
      sitesDue: raw.metrics?.sitesDue ?? sites.filter(s => s.nextReviewState && s.nextReviewState !== "future").length,
      duplicateCandidates: dupes.reduce((n, g) => n + g.jobIds.length, 0),
      needsAction: raw.metrics?.needsAction || jobs.filter(j => j.nextAction !== null).length,
    };

    const meta = raw.meta || {
      total_jobs: jobs.length,
      loaded_jobs: jobs.length,
      total_sites: sites.length,
      loaded_sites: sites.length,
    };

    return {
      jobs,
      companies,
      sites,
      dupes,
      metrics,
      meta,
      settings: raw.settings || {},
      metros: raw.metros || {},
      isDemo: raw.isDemo || false,
    };
  }

  function publishUiData(mapped) {
    const pendingExtraction = mapped.metrics?.pendingExtraction || 0;
    const failedExtraction = mapped.metrics?.failedExtraction || 0;
    Object.assign(window, {
      JH_STATUSES: STATUSES,
      JH_JOBS: mapped.jobs,
      JH_COMPANIES: mapped.companies,
      JH_SITES: mapped.sites,
      JH_DUPES: mapped.dupes,
      JH_METRICS: mapped.metrics,
      JH_META: mapped.meta,
      JH_SETTINGS: mapped.settings,
      JH_METROS: mapped.metros,
      JH_IS_DEMO: mapped.isDemo || false,
      JH_QUEUE_STATS: {
        totalOutstanding: pendingExtraction + failedExtraction,
        queued: pendingExtraction,
        running: 0,
        failed: failedExtraction,
        pending_unqueued: 0,
      },
    });
    window.dispatchEvent(new Event(UI_DATA_REFRESH_EVENT));
    window.dispatchEvent(new Event(window.JH_LLM_QUEUE_REFRESH_EVENT || "jobhunt:llm-queue-refreshed"));
  }

  async function refreshUiData() {
    const fresh = await api("/api/ui-data");
    const mapped = mapUiData(fresh);
    publishUiData(mapped);
    return mapped;
  }

  const refreshUiDataOrReload = async () => {
    try {
      await refreshUiData();
    } catch (e) {
      window.location.reload();
    }
  };

  // Show loading indicator immediately (before React mounts)
  rootEl.innerHTML = `<div class="jh-root" data-theme="${resolvedTheme}">
    <div class="jh-boot-loading">
    <div class="jh-boot-spinner"></div>
    <div style="font-size:13px;color:var(--fg-mute,#888)">Loading…</div>
  </div></div>`;

  let data = { jobs: [], companies: {}, sites: [], dupes: [], metrics: {}, settings: {} };
  let bootError = null;

  try {
    const res = await fetch("/api/ui-data");
    if (!res.ok) throw new Error(`Server returned ${res.status}: ${await res.text()}`);
    data = await res.json();
  } catch (e) {
    bootError = e.message || String(e);
  }

  if (bootError) {
    const root = ReactDOM.createRoot(rootEl);
    root.render(
      <div className="jh-root" data-theme={resolvedTheme}>
        <div className="jh-boot-error">
          <Icon.AlertTriangle size={32} />
          <h2>Could not load Jobhunt</h2>
          <p>{bootError}</p>
          <Btn kind="accent" onClick={() => window.location.reload()}>Retry</Btn>
          <div style={{ marginTop: 8, fontSize: 12, color: "var(--fg-faint)" }}>
            Check that the local service is running on port 8765.
          </div>
        </div>
      </div>
    );
    return;
  }

  const mapped = mapUiData(data);
  publishUiData(mapped);

  Object.assign(window, {
    JH_SITE_UI_REFRESH_EVENT: UI_DATA_REFRESH_EVENT,
    JH_LLM_QUEUE_REFRESH_EVENT: "jobhunt:llm-queue-refreshed",
    JH_REFRESH_UI_DATA: refreshUiData,
    JH_API: {
      api,
      mutate,
      setStatus: (jobId, status) => mutate(`/api/jobs/${jobId}/status`, { method: "PATCH", body: JSON.stringify({ status }) }),
      bulkSetStatus: (jobIds, status) => mutate("/api/jobs/bulk/status", { method: "PATCH", body: JSON.stringify({ job_ids: jobIds, status }) }),
      markDataQualityReviewed: (jobIds, note = "") => mutate("/api/jobs/bulk/data-quality-reviewed", { method: "POST", body: JSON.stringify({ job_ids: jobIds, note }) }),
      clearDataQualityReviewed: (jobIds) => mutate("/api/jobs/bulk/data-quality-reviewed", { method: "DELETE", body: JSON.stringify({ job_ids: jobIds }) }),
      bulkQueueLlm: (jobIds, mode) => mutate("/api/jobs/bulk/llm", { method: "POST", body: JSON.stringify({ job_ids: jobIds, mode }) }),
      saveSettings: (body) => api("/api/settings", { method: "PATCH", body: JSON.stringify(body) }),
      addNote: (jobId, note) => mutate(`/api/jobs/${jobId}/notes`, { method: "POST", body: JSON.stringify({ note }) }),
      archiveJob: (jobId) => mutate(`/api/jobs/${jobId}/archive`, { method: "POST" }),
      deleteJob: (jobId) => mutate(`/api/jobs/${jobId}`, { method: "DELETE" }),
      rerunExtraction: (jobId) => mutate(`/api/jobs/${jobId}/extract`, { method: "POST" }),
      recordJobOpened: (jobId) => api(`/api/jobs/${jobId}/opened`, { method: "POST" }).then(refreshUiDataOrReload),
      openJobSource: (jobId, url) => {
        window.open(url, "_blank");
        return api(`/api/jobs/${jobId}/opened`, { method: "POST" })
          .then(refreshUiDataOrReload)
          .catch((e) => window.JH_TOAST?.show(e.message, "error"));
      },
      scoreFit: (jobId) => mutate(`/api/jobs/${jobId}/fit-score`, { method: "POST" }),
      processExtractions: () => api("/api/extractions/run", { method: "POST" }),
      checkAvailability: () => api("/api/jobs/check-availability", { method: "POST" }),
      enqueueAllPending: () => api("/api/llm-queue/enqueue-all", { method: "POST" }),
      processSelected: (requestIds) => api("/api/llm-queue/process-selected", { method: "POST", body: JSON.stringify({ request_ids: requestIds || [] }) }),
      getLlmQueue: () => api("/api/llm-queue"),
      getLlmQueueAttempts: (requestId) => api(`/api/llm-queue/${encodeURIComponent(requestId)}/attempts`),
      resetRunLlmQueueRequest: (requestId) => api(`/api/llm-queue/${encodeURIComponent(requestId)}/reset-run`, { method: "POST" }),
      setLlmQueuePaused: (paused) => api("/api/llm-queue/pause", {
        method: "POST",
        body: JSON.stringify({ paused: Boolean(paused) }),
      }),
      cancelLlmQueueRequest: (requestId) => api(`/api/llm-queue/${encodeURIComponent(requestId)}/cancel`, {
        method: "POST",
      }),
      cancelAllLlmQueueRequests: () => api("/api/llm-queue/cancel-all", { method: "POST" }),
      markSiteReviewed: (site) => mutate("/site-reviews", { method: "POST", body: JSON.stringify(site) }),
      addSite: (body) => api("/api/sites", { method: "POST", body: JSON.stringify(body) }).then(refreshUiDataOrReload),
      reviewSite: (siteRef) => api("/api/sites/review", {
        method: "POST",
        body: JSON.stringify({ site_ref: String(siteRef) }),
      }).then(refreshUiDataOrReload),
      updateSite: (siteId, body) => api(`/api/sites/${encodeURIComponent(siteId)}`, { method: "PATCH", body: JSON.stringify(body) }).then(refreshUiDataOrReload),
      deleteSite: (siteId) => api(`/api/sites/${encodeURIComponent(siteId)}`, { method: "DELETE" }).then(refreshUiDataOrReload),
      decideDuplicate: (payload) => mutate("/api/duplicates/decision", { method: "POST", body: JSON.stringify(payload) }),
      createAction: (jobId, note, dueDate) => api(`/api/jobs/${jobId}/actions`, { method: "POST", body: JSON.stringify({ note, due_date: dueDate }) }).then(refreshUiDataOrReload),
      completeAction: (actionId) => api(`/api/actions/${actionId}/complete`, { method: "POST" }).then(refreshUiDataOrReload),
      snoozeAction: (actionId, days) => api(`/api/actions/${actionId}/snooze`, { method: "POST", body: JSON.stringify({ days }) }).then(refreshUiDataOrReload),
      setRating: (jobId, rating) => api(`/api/jobs/${jobId}/rating`, { method: "PATCH", body: JSON.stringify({ rating }) }).then(refreshUiDataOrReload),
    },
  });

  const root = ReactDOM.createRoot(rootEl);
  const firstRunComplete = localStorage.getItem("jobhunt.first_run_complete") === "1";
  const forceFirstRun = localStorage.getItem("jobhunt.force_first_run") === "1";
  const shouldShowFirstRun = forceFirstRun || (!firstRunComplete && JH_JOBS.length === 0 && JH_SITES.length === 0);
  root.render(<JobhuntFirstRunBootstrap shouldShow={shouldShowFirstRun} initialTheme={initialTheme} />);
})();
