// Jobhunt — Settings page

const PROVIDER_LABELS = {
  lmstudio: "LM Studio (local)",
  openai: "OpenAI",
  anthropic: "Anthropic",
  google: "Google Gemini",
  openrouter: "OpenRouter",
  custom: "Custom OpenAI-compatible",
};

const PROVIDER_HARDCODED_MODELS = {
  anthropic: ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"],
  google: ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"],
  openai: ["gpt-4o", "gpt-4o-mini", "o3", "o3-mini"],
  openrouter: ["openai/gpt-4o", "openai/gpt-4o-mini", "anthropic/claude-sonnet-4-6", "google/gemini-2.5-flash-preview-05-20"],
};

// Providers that use the local/custom base URL input
const SHOWS_BASE_URL = new Set(["lmstudio", "custom"]);
// Providers that need an API key
const NEEDS_API_KEY = new Set(["openai", "anthropic", "google", "openrouter", "custom"]);

function SettingsPage() {
  const s = window.JH_SETTINGS || {};
  const parseBool = (value, fallback) => {
    if (typeof value === "boolean") return value;
    if (value == null) return fallback;
    const normalized = String(value).toLowerCase();
    return ["1", "true", "yes", "on", "enabled"].includes(normalized);
  };

  const defaults = React.useMemo(() => ({
    llmProvider: s.llm_provider || "lmstudio",
    llmBaseUrl: s.llm_base_url || "http://127.0.0.1:1234",
    llmApiKey: s.llm_api_key || "",
    llmModel: s.llm_model || "",
    siteInterval: String(s.site_review_interval_days || 14),
    followupDays: String(s.followup_default_days || 7),
    resumeText: s.resume_text || "",
    preferredLocations: s.preferred_locations !== undefined ? s.preferred_locations : "WA, Washington, Seattle, Bellevue, Redmond, Kirkland, Bothell, Renton",
    allowRemote: parseBool(s.location_allow_remote, true),
    allowHybrid: parseBool(s.location_allow_hybrid, true),
    allowOnsite: parseBool(s.location_allow_onsite, true),
    preferredMetros: s.preferred_metros || '',
    filterEnabled: parseBool(s.location_filter_enabled, true),
    llmDebugLevel: s.llm_debug_level || "errors",
    availabilityAutoCheck: parseBool(s.availability_auto_check_enabled, true),
    availabilityIntervalDays: String(s.availability_auto_check_interval_days || 1),
    availabilityStaleDays: String(s.availability_stale_days || 21),
  }), []); // eslint-disable-line react-hooks/exhaustive-deps

  const [llmProvider, setLlmProvider] = React.useState(defaults.llmProvider);
  const [llmBaseUrl, setLlmBaseUrl] = React.useState(defaults.llmBaseUrl);
  const [llmApiKey, setLlmApiKey] = React.useState(defaults.llmApiKey);
  const [llmModel, setLlmModel] = React.useState(defaults.llmModel);
  const [siteInterval, setSiteInterval] = React.useState(defaults.siteInterval);
  const [followupDays, setFollowupDays] = React.useState(defaults.followupDays);
  const [resumeText, setResumeText] = React.useState(defaults.resumeText);
  const [preferredLocations, setPreferredLocations] = React.useState(defaults.preferredLocations);
  const [allowRemote, setAllowRemote] = React.useState(defaults.allowRemote);
  const [allowHybrid, setAllowHybrid] = React.useState(defaults.allowHybrid);
  const [allowOnsite, setAllowOnsite] = React.useState(defaults.allowOnsite);
  const [preferredMetros, setPreferredMetros] = React.useState(defaults.preferredMetros);
  const [filterEnabled, setFilterEnabled] = React.useState(defaults.filterEnabled);
  const [llmDebugLevel, setLlmDebugLevel] = React.useState(defaults.llmDebugLevel);
  const [availabilityAutoCheck, setAvailabilityAutoCheck] = React.useState(defaults.availabilityAutoCheck);
  const [availabilityIntervalDays, setAvailabilityIntervalDays] = React.useState(defaults.availabilityIntervalDays);
  const [availabilityStaleDays, setAvailabilityStaleDays] = React.useState(defaults.availabilityStaleDays);
  const [saving, setSaving] = React.useState(false);
  const [saveMsg, setSaveMsg] = React.useState(null);
  const [testResult, setTestResult] = React.useState(null);
  const [testing, setTesting] = React.useState(false);
  const [models, setModels] = React.useState([]);
  const [fetchingModels, setFetchingModels] = React.useState(false);
  const [debugEnabled, setDebugEnabled] = React.useState(() => localStorage.getItem('jh.debug') === '1');
  const [activeTab, setActiveTab] = React.useState('settings');

  function toggleDebug() {
    const next = !debugEnabled;
    setDebugEnabled(next);
    localStorage.setItem('jh.debug', next ? '1' : '0');
    if (next) setActiveTab('debug');
    else setActiveTab('settings');
  }

  // Track saved state separately so dirty resets after save without remounting
  const [savedValues, setSavedValues] = React.useState(defaults);
  const isDirtyFromSaved = (
    llmProvider !== savedValues.llmProvider ||
    llmBaseUrl !== savedValues.llmBaseUrl ||
    llmApiKey !== savedValues.llmApiKey ||
    llmModel !== savedValues.llmModel ||
    siteInterval !== savedValues.siteInterval ||
    followupDays !== savedValues.followupDays ||
    resumeText !== savedValues.resumeText ||
    preferredLocations !== savedValues.preferredLocations ||
    allowRemote !== savedValues.allowRemote ||
    allowHybrid !== savedValues.allowHybrid ||
    allowOnsite !== savedValues.allowOnsite ||
    preferredMetros !== savedValues.preferredMetros ||
    filterEnabled !== savedValues.filterEnabled ||
    llmDebugLevel !== savedValues.llmDebugLevel ||
    availabilityAutoCheck !== savedValues.availabilityAutoCheck ||
    availabilityIntervalDays !== savedValues.availabilityIntervalDays ||
    availabilityStaleDays !== savedValues.availabilityStaleDays
  );

  async function saveSettings(next) {
    setSaving(true);
    setSaveMsg(null);
    try {
      const res = await fetch("/api/settings", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          llm_provider: next.llmProvider,
          llm_base_url: next.llmBaseUrl,
          llm_api_key: next.llmApiKey,
          llm_model: next.llmModel,
          site_review_interval_days: Number(next.siteInterval),
          followup_default_days: Number(next.followupDays),
          resume_text: next.resumeText,
          preferred_locations: next.preferredLocations,
          location_allow_remote: next.allowRemote,
          location_allow_hybrid: next.allowHybrid,
          location_allow_onsite: next.allowOnsite,
          preferred_metros: next.preferredMetros,
          location_filter_enabled: String(next.filterEnabled),
          llm_debug_level: next.llmDebugLevel,
          availability_auto_check_enabled: next.availabilityAutoCheck,
          availability_auto_check_interval_days: Number(next.availabilityIntervalDays),
          availability_stale_days: Number(next.availabilityStaleDays),
        }),
      });
      if (res.ok) {
        setSavedValues(next);
        // Update the in-memory global so other components see the new settings
        Object.assign(window.JH_SETTINGS || {}, {
          llm_provider: next.llmProvider,
          llm_base_url: next.llmBaseUrl,
          llm_api_key: next.llmApiKey,
          llm_model: next.llmModel,
          site_review_interval_days: Number(next.siteInterval),
          followup_default_days: Number(next.followupDays),
          resume_text: next.resumeText,
          preferred_locations: next.preferredLocations,
          location_allow_remote: String(next.allowRemote),
          location_allow_hybrid: String(next.allowHybrid),
          location_allow_onsite: String(next.allowOnsite),
          llm_debug_level: next.llmDebugLevel,
          availability_auto_check_enabled: String(next.availabilityAutoCheck),
          availability_auto_check_interval_days: Number(next.availabilityIntervalDays),
          availability_stale_days: Number(next.availabilityStaleDays),
        });
        setSaveMsg({ kind: "success", text: "All changes saved" });
      } else {
        const err = await res.text();
        setSaveMsg({ kind: "error", text: err || "Autosave failed" });
      }
    } catch (e) {
      setSaveMsg({ kind: "error", text: e.message });
    } finally {
      setSaving(false);
    }
  }

  React.useEffect(() => {
    if (!isDirtyFromSaved) return;
    setSaveMsg({ kind: "saving", text: "Saving changes…" });
    const next = {
      llmProvider,
      llmBaseUrl,
      llmApiKey,
      llmModel,
      siteInterval,
      followupDays,
      resumeText,
      preferredLocations,
      allowRemote,
      allowHybrid,
      allowOnsite,
      preferredMetros,
      filterEnabled,
      llmDebugLevel,
      availabilityAutoCheck,
      availabilityIntervalDays,
      availabilityStaleDays,
    };
    const timer = setTimeout(() => {
      saveSettings(next);
    }, 700);
    return () => clearTimeout(timer);
  }, [llmProvider, llmBaseUrl, llmApiKey, llmModel, siteInterval, followupDays, resumeText, preferredLocations, allowRemote, allowHybrid, allowOnsite, preferredMetros, filterEnabled, llmDebugLevel, availabilityAutoCheck, availabilityIntervalDays, availabilityStaleDays]); // eslint-disable-line react-hooks/exhaustive-deps

  async function _callTestLlm(quick = false) {
    const res = await fetch("/api/settings/test-llm", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider: llmProvider, base_url: llmBaseUrl, api_key: llmApiKey, model: llmModel, quick }),
    });
    return res.json();
  }

  // Populate model list when provider changes (or on mount)
  React.useEffect(() => {
    const hardcoded = PROVIDER_HARDCODED_MODELS[llmProvider];
    if (hardcoded) {
      setModels(hardcoded);
      return;
    }
    _callTestLlm(true)
      .then(data => { if (data.ok && data.models?.length > 0) setModels(data.models); })
      .catch(() => {});
  }, [llmProvider]); // eslint-disable-line react-hooks/exhaustive-deps

  async function handleTestLlm() {
    setTesting(true);
    setTestResult(null);
    try {
      const data = await _callTestLlm();
      setTestResult(data);
      if (data.ok && data.models?.length > 0) setModels(data.models);
    } catch (e) {
      setTestResult({ ok: false, error: e.message });
    } finally {
      setTesting(false);
    }
  }

  async function handleFetchModels() {
    setFetchingModels(true);
    try {
      const data = await _callTestLlm(true);
      if (data.ok && data.models?.length > 0) {
        setModels(data.models);
      } else {
        window.JH_TOAST?.show(data.error || "No models returned — is LM Studio running?", "error");
      }
    } catch (e) {
      window.JH_TOAST?.show(e.message, "error");
    } finally {
      setFetchingModels(false);
    }
  }

  const lastCapture = (window.JH_JOBS || []).reduce((latest, j) => {
    return !latest || j.capturedAt > latest ? j.capturedAt : latest;
  }, null);

  const tabs = debugEnabled ? ['Settings', 'Debug'] : [];

  return (
    <div style={{ overflow: "auto", flex: 1 }}>
      {tabs.length > 0 && (
        <div style={{ display: 'flex', gap: 0, borderBottom: '1px solid var(--border)', padding: '0 28px', background: 'var(--bg)' }}>
          {tabs.map(tab => {
            const id = tab.toLowerCase();
            const active = activeTab === id;
            return (
              <button key={id} onClick={() => setActiveTab(id)} style={{
                background: 'none', border: 'none', borderBottom: active ? '2px solid var(--accent)' : '2px solid transparent',
                color: active ? 'var(--fg)' : 'var(--fg-mute)', cursor: 'pointer',
                fontSize: 13, fontWeight: active ? 600 : 400, padding: '10px 16px 8px', marginBottom: -1,
              }}>{tab}</button>
            );
          })}
        </div>
      )}
      {activeTab === 'debug' ? (
        <DebugTab llmDebugLevel={llmDebugLevel} onToggleVerbose={() => {
          const next = llmDebugLevel === 'full' ? 'errors' : 'full';
          setLlmDebugLevel(next);
          saveSettings({ llm_debug_level: next });
        }} />
      ) : (
      <div className="jh-settings">
        <div style={{ display: "flex", justifyContent: "flex-end", minHeight: 18, fontSize: 12, color: saveMsg?.kind === "error" ? "var(--st-rejected)" : saving || saveMsg?.kind === "saving" ? "var(--fg-mute)" : "var(--st-offer)" }}>
          {saving ? "Saving changes…" : saveMsg?.text || "All changes saved"}
        </div>
        <Section title="Local service" desc="The local Jobhunt daemon that the Chrome extension talks to.">
          <Row>
            <span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
              <span style={{ width: 8, height: 8, borderRadius: 50, background: "var(--st-offer)", boxShadow: "0 0 0 3px rgba(79,174,111,0.18)" }}></span>
              <span style={{ color: "var(--fg-strong)" }}>Running</span>
              <span style={{ color: "var(--fg-mute)", fontFamily: "var(--font-mono)", fontSize: 11.5 }}>{s.server_url || "http://127.0.0.1:8765"}</span>
            </span>
            <Btn size="sm" icon={<Icon.Refresh size={11} />} onClick={() => window.location.reload()}>Refresh</Btn>
          </Row>
        </Section>

        <Section title="Chrome extension" desc="The page-capture extension. Pair with the daemon to push new jobs.">
          <Row>
            <span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
              <span style={{ width: 8, height: 8, borderRadius: 50, background: lastCapture ? "var(--st-offer)" : "var(--fg-faint)" }}></span>
              <span style={{ color: "var(--fg-strong)" }}>{lastCapture ? "Active" : "No captures yet"}</span>
              {lastCapture && <span style={{ color: "var(--fg-mute)" }}>Last capture: {lastCapture.slice(0, 10)}</span>}
            </span>
          </Row>
        </Section>

        <Section title="Availability checks" desc="Automatically checks older active jobs for expired postings or redirects.">
          <div className="jh-row" style={{ gap: 12, alignItems: "center", flexWrap: "wrap" }}>
            <label className="jh-label" style={{ width: "auto", margin: 0 }}>
              <input type="checkbox" checked={availabilityAutoCheck} onChange={e => setAvailabilityAutoCheck(e.target.checked)} />
              {" "}Auto-check stale jobs
            </label>
            <span style={{ color: "var(--fg-faint)", fontSize: 11 }}>
              Last auto-check: {s.availability_last_auto_check_at ? fmtDateTime(s.availability_last_auto_check_at) : "—"}
            </span>
          </div>
          <div className="jh-row" style={{ gap: 16 }}>
            <div style={{ flex: 1 }}>
              <div className="jh-label">Run at most every</div>
              <div className="jh-input" style={{ paddingRight: 4 }}>
                <input type="number" min="1" value={availabilityIntervalDays} onChange={e => setAvailabilityIntervalDays(e.target.value)} style={{ width: 44, background: "transparent", border: "none", outline: "none", color: "inherit" }} />
                <span style={{ color: "var(--fg-mute)" }}>days</span>
              </div>
            </div>
            <div style={{ flex: 1 }}>
              <div className="jh-label">Consider stale after</div>
              <div className="jh-input" style={{ paddingRight: 4 }}>
                <input type="number" min="1" value={availabilityStaleDays} onChange={e => setAvailabilityStaleDays(e.target.value)} style={{ width: 44, background: "transparent", border: "none", outline: "none", color: "inherit" }} />
                <span style={{ color: "var(--fg-mute)" }}>days since capture</span>
              </div>
            </div>
          </div>
        </Section>

        <Section title="LLM provider" desc="Model used for structured extraction from captured job pages.">
          <div>
            <div className="jh-label">Provider</div>
            <select
              value={llmProvider}
              onChange={e => { setLlmProvider(e.target.value); setTestResult(null); setModels([]); }}
              style={{
                width: "100%", height: 30, padding: "0 8px",
                background: "var(--bg-elev)", border: "1px solid var(--border)",
                borderRadius: "var(--r-2)", color: "var(--fg)", fontSize: 13,
              }}
            >
              {Object.entries(PROVIDER_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </div>

          {SHOWS_BASE_URL.has(llmProvider) && (
            <div>
              <div className="jh-label">Base URL</div>
              <div className="jh-input">
                <input value={llmBaseUrl} onChange={e => setLlmBaseUrl(e.target.value)} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "inherit" }} />
              </div>
            </div>
          )}

          {!SHOWS_BASE_URL.has(llmProvider) && llmProvider !== "anthropic" && llmProvider !== "google" && (
            <div style={{ fontSize: 11, color: "var(--fg-faint)" }}>
              Endpoint: {llmProvider === "openai" ? "https://api.openai.com" : llmProvider === "openrouter" ? "https://openrouter.ai/api" : "(custom)"}
            </div>
          )}

          {NEEDS_API_KEY.has(llmProvider) && (
            <div>
              <div className="jh-label">API key</div>
              <div className="jh-input">
                <input
                  type="password"
                  value={llmApiKey}
                  onChange={e => setLlmApiKey(e.target.value)}
                  placeholder={llmProvider === "openai" ? "sk-…" : llmProvider === "anthropic" ? "sk-ant-…" : "API key"}
                  style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "inherit", fontFamily: "var(--font-mono)" }}
                />
              </div>
            </div>
          )}

          <div>
            <div className="jh-label">Model</div>
            <select
              value={llmModel}
              onChange={e => setLlmModel(e.target.value)}
              style={{
                width: "100%", height: 30, padding: "0 8px",
                background: "var(--bg-elev)", border: "1px solid var(--border)",
                borderRadius: "var(--r-2)", color: "var(--fg)",
                fontFamily: "var(--font-mono)", fontSize: 12,
              }}
            >
              {models.length === 0 && (
                <option value={llmModel}>{llmModel || "— no models loaded —"}</option>
              )}
              {models.length > 0 && !models.includes(llmModel) && llmModel && (
                <option value={llmModel}>{llmModel} ⚠ not in list</option>
              )}
              {models.map(m => <option key={m} value={m}>{m}</option>)}
            </select>
            {!PROVIDER_HARDCODED_MODELS[llmProvider] && (
              <div style={{ marginTop: 4 }}>
                <Btn size="sm" kind="ghost" icon={<Icon.Refresh size={11} />} onClick={handleFetchModels} disabled={fetchingModels}>
                  {fetchingModels ? "Loading models…" : models.length > 0 ? `${models.length} model${models.length !== 1 ? "s" : ""} loaded` : "Load models from server"}
                </Btn>
              </div>
            )}
          </div>

          <Row style={{ marginTop: 4 }}>
            <Btn size="sm" kind="accent" icon={<Icon.Check size={11} />} onClick={handleTestLlm} disabled={testing}>
              {testing ? "Testing…" : "Test connection"}
            </Btn>
            {testResult && (
              <span style={{ fontSize: 12, display: "inline-flex", flexDirection: "column", gap: 4 }}>
                {(() => {
                  const noModels = testResult.ok && (testResult.models?.length || 0) === 0;
                  const connOk = testResult.ok && !noModels;
                  const connColor = connOk ? "var(--st-offer)" : "var(--st-rejected)";
                  const providerName = PROVIDER_LABELS[llmProvider] || llmProvider;
                  const connText = !testResult.ok ? testResult.error
                    : noModels ? `Connected to ${providerName} but no models found`
                    : `${providerName} · ${testResult.models.length} model(s)`;
                  return (
                    <span style={{ color: connColor, display: "inline-flex", gap: 6, alignItems: "center" }}>
                      <span style={{ width: 6, height: 6, borderRadius: 50, flexShrink: 0, background: connColor }}></span>
                      {connText}
                    </span>
                  );
                })()}
                {testResult.ok && testResult.models?.length > 0 && llmModel && !testResult.models.includes(llmModel) && (
                  <span style={{ color: "var(--st-rejected)", display: "inline-flex", gap: 6, alignItems: "center", fontFamily: "var(--font-mono)", fontSize: 11 }}>
                    <span style={{ flexShrink: 0, fontWeight: "bold" }}>✗</span>
                    Selected model "{llmModel}" not in list
                  </span>
                )}
                {testResult.ok && testResult.modelTests?.map((t, i) => {
                  const color = t.status === "pass" ? "var(--st-offer)" : t.status === "warn" ? "var(--st-screening)" : "var(--st-rejected)";
                  const symbol = t.status === "pass" ? "✓" : t.status === "warn" ? "⚠" : "✗";
                  return (
                    <span key={i} style={{ display: "inline-flex", gap: 6, alignItems: "flex-start", fontFamily: "var(--font-mono)", fontSize: 11 }}>
                      <span style={{ color, flexShrink: 0, fontWeight: "bold" }}>{symbol}</span>
                      <span><span style={{ color: "var(--fg-mute)" }}>{t.name}:</span> <span style={{ color }}>{t.message}</span></span>
                    </span>
                  );
                })}
              </span>
            )}
          </Row>
          <div>
            <div className="jh-label">Debug logging</div>
            <select
              value={llmDebugLevel}
              onChange={e => setLlmDebugLevel(e.target.value)}
              style={{
                width: "100%", height: 30, padding: "0 8px",
                background: "var(--bg-elev)", border: "1px solid var(--border)",
                borderRadius: "var(--r-2)", color: "var(--fg)",
                fontFamily: "var(--font-mono)", fontSize: 12,
              }}
            >
              <option value="off">Off</option>
              <option value="errors">Errors only</option>
              <option value="full">Full</option>
            </select>
            <div style={{ fontSize: 11, color: "var(--fg-faint)", marginTop: 4 }}>
              Writes LLM attempt history to the database. Failed attempts are also appended to the debug log under the app config directory.
            </div>
          </div>
        </Section>

        <Section title="Resume" desc="Paste your resume as plain text. Jobs are scored 0-100 for fit against it automatically after extraction.">
          <div>
            <div className="jh-label">Resume text</div>
            <div className="jh-input" style={{ alignItems: "stretch", padding: 0, height: "auto" }}>
              <textarea
                value={resumeText}
                onChange={e => setResumeText(e.target.value)}
                placeholder="Paste your full resume here as plain text…"
                rows={14}
                style={{
                  width: "100%",
                  minHeight: 200,
                  padding: "8px 10px",
                  background: "transparent",
                  border: "none",
                  outline: "none",
                  color: "inherit",
                  fontFamily: "var(--font-mono)",
                  fontSize: 12,
                  resize: "vertical",
                  lineHeight: 1.45,
                }}
              />
            </div>
            <div style={{ fontSize: 11, color: "var(--fg-faint)", marginTop: 4 }}>
              {resumeText.trim()
                ? "Saved jobs will be re-scored when re-extracted, or score them now from a job's detail view."
                : "Add a resume to enable fit scoring."}
            </div>
          </div>
        </Section>

        <Section title="Location filter" desc="Comma-separated city/state/region names. Extraction filters job locations to these — only matching locations are stored and used to set remote/onsite status. Changing this requires re-running extraction on existing jobs.">
          <LocationPicker
            preferredMetros={preferredMetros} setPreferredMetros={setPreferredMetros}
            preferredLocations={preferredLocations} setPreferredLocations={setPreferredLocations}
            filterEnabled={filterEnabled} setFilterEnabled={setFilterEnabled}
            allowRemote={allowRemote} setAllowRemote={setAllowRemote}
            allowHybrid={allowHybrid} setAllowHybrid={setAllowHybrid}
            allowOnsite={allowOnsite} setAllowOnsite={setAllowOnsite}
          />
        </Section>

        <Section title="Defaults" desc="Per-feature defaults applied to new records.">
          <div className="jh-row" style={{ gap: 16 }}>
            <div style={{ flex: 1 }}>
              <div className="jh-label">Site review interval</div>
              <div className="jh-input" style={{ paddingRight: 4 }}>
                <input type="number" value={siteInterval} onChange={e => setSiteInterval(e.target.value)} style={{ width: 40, background: "transparent", border: "none", outline: "none", color: "inherit" }} />
                <span style={{ color: "var(--fg-mute)" }}>days</span>
                <span style={{ marginLeft: "auto", color: "var(--fg-faint)" }}>used for new sites</span>
              </div>
            </div>
            <div style={{ flex: 1 }}>
              <div className="jh-label">Follow-up after applying</div>
              <div className="jh-input" style={{ paddingRight: 4 }}>
                <input type="number" value={followupDays} onChange={e => setFollowupDays(e.target.value)} style={{ width: 40, background: "transparent", border: "none", outline: "none", color: "inherit" }} />
                <span style={{ color: "var(--fg-mute)" }}>days</span>
              </div>
            </div>
          </div>
        </Section>

        <Section title="Demo mode" desc="Explore Jobhunt with pre-loaded sample data, or switch back to your real database.">
          <Row>
            {window.JH_IS_DEMO ? (
              <>
                <span style={{ fontSize: 13, color: 'var(--fg-mute)', flex: 1 }}>🎮 Currently using demo data</span>
                <Btn size="sm" kind="accent" onClick={() => window.switchDb('user')}>Switch to my data</Btn>
                <Btn size="sm" kind="ghost" onClick={async () => {
                  if (!window.confirm('Reset demo data to its original state?')) return;
                  await fetch('/api/db/reseed-demo', { method: 'POST' });
                  window.location.reload();
                }}>Reset demo</Btn>
              </>
            ) : (
              <>
                <span style={{ fontSize: 13, color: 'var(--fg-mute)', flex: 1 }}>Load sample jobs to explore the app</span>
                <Btn size="sm" onClick={() => window.switchDb('demo')}>Load demo data</Btn>
              </>
            )}
          </Row>
        </Section>

        <Section title="Data" desc="Local data tools. All operations write to the SQLite DB.">
          <Row>
            <Btn size="sm" icon={<Icon.External size={11} />} onClick={() => window.open("/exports/jobs.csv", "_blank")}>Export CSV</Btn>
          </Row>
          <DKV k="Config directory" v={s.config_dir || "~/.config/jobhunt"} />
          <DKV k="Local DB path" v={s.db_path || "~/.config/jobhunt/jobhunt.db"} />
          <DKV k="LLM debug log" v={s.llm_debug_log_path || "~/.config/jobhunt/jobhunt-llm-debug.log"} />
          <DKV k="Records" v={`${(window.JH_JOBS || []).length} jobs · ${(window.JH_SITES || []).length} site reviews`} />
        </Section>

        <Section title="App info" desc="">
          <DKV k="Version" v={s.version || "unknown"} onDoubleClick={toggleDebug} title={debugEnabled ? "Double-click to disable debug mode" : "Double-click to enable debug mode"} />
          <DKV k="Build" v="local development" />
        </Section>
      </div>
      )}
    </div>
  );
}

function DebugTab({ llmDebugLevel, onToggleVerbose }) {
  const [stats, setStats] = React.useState(null);

  React.useEffect(() => {
    fetch('/api/debug/stats').then(r => r.json()).then(setStats).catch(() => {});
  }, []);

  function fmt(n) { return n == null ? '—' : Number(n).toLocaleString(); }
  function fmtBytes(n) {
    if (n == null) return '—';
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
    return `${(n / 1024 / 1024).toFixed(1)} MB`;
  }

  const jobStatus = Object.fromEntries((stats?.jobsByStatus || []).map(r => [r.status, r.n]));
  const llmStatus = Object.fromEntries((stats?.llmCounts || []).map(r => [r.status, r.n]));
  const extractStatus = Object.fromEntries((stats?.jobsByExtraction || []).map(r => [r.extraction_status, r.n]));
  const verbose = llmDebugLevel === 'full';

  const col = { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0 32px', maxWidth: 360 };
  const row = { display: 'flex', justifyContent: 'space-between', padding: '3px 0', fontSize: 13, borderBottom: '1px solid var(--border)' };
  const head = { fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--fg-mute)', margin: '18px 0 6px' };

  return (
    <div className="jh-settings">
      <Section title="Database" desc="Live counts from the local SQLite database.">
        <div style={col}>
          <div>
            <div style={head}>Jobs by status</div>
            {['saved','applied','interview','offer','rejected','archived'].map(s => (
              <div key={s} style={row}><span>{s}</span><span style={{ fontFamily: 'var(--font-mono)' }}>{fmt(jobStatus[s])}</span></div>
            ))}
          </div>
          <div>
            <div style={head}>Extraction</div>
            {['pending','running','succeeded','failed'].map(s => (
              <div key={s} style={row}><span>{s}</span><span style={{ fontFamily: 'var(--font-mono)' }}>{fmt(extractStatus[s])}</span></div>
            ))}
            <div style={head}>LLM requests</div>
            {['pending','running','succeeded','failed','retry_exhausted'].map(s => (
              <div key={s} style={row}><span>{s}</span><span style={{ fontFamily: 'var(--font-mono)' }}>{fmt(llmStatus[s])}</span></div>
            ))}
          </div>
        </div>
        <div style={{ marginTop: 16 }}>
          <DKV k="Captures" v={fmt(stats?.captureCount)} />
          <DKV k="DB size" v={fmtBytes(stats?.dbSize)} />
          <DKV k="DB path" v={stats?.dbPath || '—'} />
        </div>
      </Section>

      <Section title="Logging" desc="Controls verbosity of LLM attempt logging to the debug log file.">
        <Row>
          <Btn size="sm" variant={verbose ? 'primary' : undefined} onClick={onToggleVerbose}>
            {verbose ? 'Full (verbose)' : 'Errors only'}
          </Btn>
          <span style={{ fontSize: 12, color: 'var(--fg-mute)' }}>llm_debug_level = {llmDebugLevel}</span>
        </Row>
      </Section>

      <Section title="Onboarding" desc="Reset the first-run welcome dialog. Takes effect on next app launch.">
        <Row>
          <Btn size="sm" onClick={() => {
            localStorage.removeItem(window.WELCOME_KEY || 'jh.welcome_dismissed');
            window.JH_TOAST?.show('Onboarding reset — will show on next launch', 'info');
          }}>Reset onboarding</Btn>
        </Row>
      </Section>
    </div>
  );
}

function Section({ title, desc, children }) {
  return (
    <div className="jh-set-section">
      <div>
        <h3>{title}</h3>
        {desc && <p className="desc">{desc}</p>}
      </div>
      <div className="jh-set-body">{children}</div>
    </div>
  );
}

function Row({ children, style }) {
  return <div style={{ display: "flex", alignItems: "center", gap: 8, ...style }}>{children}</div>;
}

function DKV({ k, v, onDoubleClick, title }) {
  return (
    <div onDoubleClick={onDoubleClick} title={title} style={{ display: "flex", alignItems: "center", gap: 12, fontSize: 12, cursor: onDoubleClick ? "default" : undefined }}>
      <span style={{ color: "var(--fg-mute)", width: 110 }}>{k}</span>
      <span data-mono style={{ color: "var(--fg)" }}>{v}</span>
    </div>
  );
}

Object.assign(window, { SettingsPage });
