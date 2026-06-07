// Jobhunt — Settings page

const PROVIDER_LABELS = {
  lmstudio: "LM Studio (local)",
  openai: "OpenAI",
  anthropic: "Anthropic",
  google: "Google Gemini",
  openrouter: "OpenRouter",
  custom: "Custom OpenAI-compatible",
};

// All cloud providers fetch their model list dynamically from their APIs.
// Hardcode only lmstudio/custom (no public catalog endpoint).
const PROVIDER_HARDCODED_MODELS = {};

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
    llmApiKeys: {
      openai: s.llm_api_key_openai || "",
      anthropic: s.llm_api_key_anthropic || "",
      google: s.llm_api_key_google || "",
      openrouter: s.llm_api_key_openrouter || "",
      custom: s.llm_api_key_custom || "",
    },
    llmModel: s.llm_model || "",
    siteInterval: String(s.site_review_interval_days || 14),
    followupDays: String(s.followup_default_days || 7),
    preferredLocations: s.preferred_locations !== undefined ? s.preferred_locations : "WA, Washington, Seattle, Bellevue, Redmond, Kirkland, Bothell, Renton",
    allowRemote: parseBool(s.location_allow_remote, true),
    allowHybrid: parseBool(s.location_allow_hybrid, true),
    allowOnsite: parseBool(s.location_allow_onsite, true),
    preferredMetros: s.preferred_metros || '',
    filterEnabled: parseBool(s.location_filter_enabled, true),
    llmDebugLevel: s.llm_debug_level || "errors",
    llmPriceInput: s.llm_price_input || "0",
    llmPriceOutput: s.llm_price_output || "0",
    llmOpenrouterFreeRotate: s.llm_openrouter_free_rotate === "true",
    availabilityAutoCheck: parseBool(s.availability_auto_check_enabled, true),
    availabilityIntervalDays: String(s.availability_auto_check_interval_days || 1),
    availabilityStaleDays: String(s.availability_stale_days || 21),
  }), []); // eslint-disable-line react-hooks/exhaustive-deps

  const [llmProvider, setLlmProvider] = React.useState(defaults.llmProvider);
  const [llmBaseUrl, setLlmBaseUrl] = React.useState(defaults.llmBaseUrl);
  const [llmApiKeys, setLlmApiKeys] = React.useState(defaults.llmApiKeys);
  const llmApiKey = llmApiKeys[llmProvider] || "";
  function setLlmApiKey(val) {
    setLlmApiKeys(prev => ({ ...prev, [llmProvider]: val }));
  }
  const [llmModel, setLlmModel] = React.useState(defaults.llmModel);
  const [siteInterval, setSiteInterval] = React.useState(defaults.siteInterval);
  const [followupDays, setFollowupDays] = React.useState(defaults.followupDays);
  const [preferredLocations, setPreferredLocations] = React.useState(defaults.preferredLocations);
  const [allowRemote, setAllowRemote] = React.useState(defaults.allowRemote);
  const [allowHybrid, setAllowHybrid] = React.useState(defaults.allowHybrid);
  const [allowOnsite, setAllowOnsite] = React.useState(defaults.allowOnsite);
  const [preferredMetros, setPreferredMetros] = React.useState(defaults.preferredMetros);
  const [filterEnabled, setFilterEnabled] = React.useState(defaults.filterEnabled);
  const [llmDebugLevel, setLlmDebugLevel] = React.useState(defaults.llmDebugLevel);
  const [llmPriceInput, setLlmPriceInput] = React.useState(defaults.llmPriceInput);
  const [llmPriceOutput, setLlmPriceOutput] = React.useState(defaults.llmPriceOutput);
  const [llmOpenrouterFreeRotate, setLlmOpenrouterFreeRotate] = React.useState(defaults.llmOpenrouterFreeRotate);
  const [availabilityAutoCheck, setAvailabilityAutoCheck] = React.useState(defaults.availabilityAutoCheck);
  const [availabilityIntervalDays, setAvailabilityIntervalDays] = React.useState(defaults.availabilityIntervalDays);
  const [availabilityStaleDays, setAvailabilityStaleDays] = React.useState(defaults.availabilityStaleDays);
  const [saving, setSaving] = React.useState(false);
  const [saveMsg, setSaveMsg] = React.useState(null);
  const [testResult, setTestResult] = React.useState(null);
  const [testing, setTesting] = React.useState(false);
  const [models, setModels] = React.useState([]);
  const [fetchingModels, setFetchingModels] = React.useState(false);
  const [contextInfo, setContextInfo] = React.useState(null);
  const [debugEnabled, setDebugEnabled] = React.useState(() => localStorage.getItem('jh.debug') === '1');
  const [activeTab, setActiveTab] = React.useState('settings');
  const [consentPending, setConsentPending] = React.useState(null);
  const [reQueuePrompt, setReQueuePrompt] = React.useState(null); // nextProvider when leaving apple

  const CLOUD_PROVIDERS = new Set(['anthropic', 'google', 'openrouter', 'openai']);

  async function handleProviderChange(nextProvider) {
    setTestResult(null);
    setModels([]);
    setLlmModel("");
    // When leaving Apple, prompt to re-queue jobs before changing provider
    if (llmProvider === "apple" && nextProvider !== "apple") {
      setReQueuePrompt(nextProvider);
      return;
    }
    if (!CLOUD_PROVIDERS.has(nextProvider)) {
      setLlmProvider(nextProvider);
      return;
    }
    try {
      const res = await fetch(`/api/settings/llm-consent/${nextProvider}`);
      const data = await res.json();
      if (data.consented) {
        setLlmProvider(nextProvider);
      } else {
        setConsentPending(nextProvider);
      }
    } catch {
      // On error, allow the change (fail open — consent is best-effort UI)
      setLlmProvider(nextProvider);
    }
  }

  async function finishProviderChange(nextProvider) {
    if (!CLOUD_PROVIDERS.has(nextProvider)) {
      setLlmProvider(nextProvider);
      return;
    }
    try {
      const res = await fetch(`/api/settings/llm-consent/${nextProvider}`);
      const data = await res.json();
      if (data.consented) { setLlmProvider(nextProvider); }
      else { setConsentPending(nextProvider); }
    } catch { setLlmProvider(nextProvider); }
  }

  async function handleReQueueAndSwitch(scope, nextProvider) {
    setReQueuePrompt(null);
    if (scope !== "skip") {
      try {
        const body = scope === "apple" ? { model: "apple-foundation-models" } : {};
        await fetch("/api/jobs/bulk/reset-extraction", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
      } catch { /* best-effort */ }
    }
    finishProviderChange(nextProvider);
  }

  async function handleConsentAccept() {
    const provider = consentPending;
    setConsentPending(null);
    try {
      await fetch(`/api/settings/llm-consent/${provider}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ consented: true }),
      });
    } catch { /* ignore — provider change still goes through */ }
    setLlmProvider(provider);
  }

  function handleConsentDecline() {
    setConsentPending(null);
    // Leave llmProvider unchanged (reverts to whatever it was before)
  }

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
    JSON.stringify(llmApiKeys) !== JSON.stringify(savedValues.llmApiKeys) ||
    llmModel !== savedValues.llmModel ||
    siteInterval !== savedValues.siteInterval ||
    followupDays !== savedValues.followupDays ||
    preferredLocations !== savedValues.preferredLocations ||
    allowRemote !== savedValues.allowRemote ||
    allowHybrid !== savedValues.allowHybrid ||
    allowOnsite !== savedValues.allowOnsite ||
    preferredMetros !== savedValues.preferredMetros ||
    filterEnabled !== savedValues.filterEnabled ||
    llmDebugLevel !== savedValues.llmDebugLevel ||
    llmPriceInput !== savedValues.llmPriceInput ||
    llmPriceOutput !== savedValues.llmPriceOutput ||
    llmOpenrouterFreeRotate !== savedValues.llmOpenrouterFreeRotate ||
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
          llm_api_key_openai: next.llmApiKeys.openai || "",
          llm_api_key_anthropic: next.llmApiKeys.anthropic || "",
          llm_api_key_google: next.llmApiKeys.google || "",
          llm_api_key_openrouter: next.llmApiKeys.openrouter || "",
          llm_api_key_custom: next.llmApiKeys.custom || "",
          llm_model: next.llmModel,
          site_review_interval_days: Number(next.siteInterval),
          followup_default_days: Number(next.followupDays),
          preferred_locations: next.preferredLocations,
          location_allow_remote: next.allowRemote,
          location_allow_hybrid: next.allowHybrid,
          location_allow_onsite: next.allowOnsite,
          preferred_metros: next.preferredMetros,
          location_filter_enabled: String(next.filterEnabled),
          llm_debug_level: next.llmDebugLevel,
          llm_price_input: next.llmPriceInput,
          llm_price_output: next.llmPriceOutput,
          llm_openrouter_free_rotate: String(next.llmOpenrouterFreeRotate),
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
          llm_api_key_openai: next.llmApiKeys.openai || "",
          llm_api_key_anthropic: next.llmApiKeys.anthropic || "",
          llm_api_key_google: next.llmApiKeys.google || "",
          llm_api_key_openrouter: next.llmApiKeys.openrouter || "",
          llm_api_key_custom: next.llmApiKeys.custom || "",
          llm_model: next.llmModel,
          site_review_interval_days: Number(next.siteInterval),
          followup_default_days: Number(next.followupDays),
          preferred_locations: next.preferredLocations,
          location_allow_remote: String(next.allowRemote),
          location_allow_hybrid: String(next.allowHybrid),
          location_allow_onsite: String(next.allowOnsite),
          llm_debug_level: next.llmDebugLevel,
          llm_price_input: next.llmPriceInput,
          llm_price_output: next.llmPriceOutput,
          llm_openrouter_free_rotate: String(next.llmOpenrouterFreeRotate),
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
      llmApiKeys,
      llmModel,
      siteInterval,
      followupDays,
      preferredLocations,
      allowRemote,
      allowHybrid,
      allowOnsite,
      preferredMetros,
      filterEnabled,
      llmDebugLevel,
      llmPriceInput,
      llmPriceOutput,
      llmOpenrouterFreeRotate,
      availabilityAutoCheck,
      availabilityIntervalDays,
      availabilityStaleDays,
    };
    const timer = setTimeout(() => {
      saveSettings(next);
    }, 700);
    return () => clearTimeout(timer);
  }, [llmProvider, llmBaseUrl, llmApiKeys, llmModel, siteInterval, followupDays, preferredLocations, allowRemote, allowHybrid, allowOnsite, preferredMetros, filterEnabled, llmDebugLevel, llmPriceInput, llmPriceOutput, llmOpenrouterFreeRotate, availabilityAutoCheck, availabilityIntervalDays, availabilityStaleDays]); // eslint-disable-line react-hooks/exhaustive-deps

  async function _callTestLlm(quick = false) {
    const res = await fetch("/api/settings/test-llm", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider: llmProvider, base_url: llmBaseUrl, api_key: llmApiKey, model: llmModel, quick }),
    });
    return res.json();
  }

  // Populate model list when provider or free-rotate setting changes.
  // The cancelled flag prevents a slow in-flight response from overwriting
  // a newer fetch that already resolved.
  React.useEffect(() => {
    setModels([]);
    // Cloud providers that need a key: don't even try without one
    if (NEEDS_API_KEY.has(llmProvider) && !SHOWS_BASE_URL.has(llmProvider) && !llmApiKey) return;
    let cancelled = false;
    const promise = (llmProvider === 'openrouter' && llmOpenrouterFreeRotate)
      ? _fetchFreeModels()
      : _callTestLlm(true);
    promise
      .then(data => { if (!cancelled && data.ok && data.models?.length > 0) setModels([...data.models].sort()); })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [llmProvider, llmOpenrouterFreeRotate, llmApiKey]); // eslint-disable-line react-hooks/exhaustive-deps

  // Fetch context window info when model or provider changes
  React.useEffect(() => {
    setContextInfo(null);
    fetch('/api/settings/model-context')
      .then(r => r.json())
      .then(data => setContextInfo(data))
      .catch(() => {});
  }, [llmModel, llmProvider]); // eslint-disable-line react-hooks/exhaustive-deps

  async function _fetchFreeModels() {
    const r = await fetch('/api/settings/free-models');
    return r.json();
  }

  async function handleTestLlm() {
    setTesting(true);
    setTestResult(null);
    try {
      const data = await ((llmProvider === 'openrouter' && llmOpenrouterFreeRotate) ? _fetchFreeModels() : _callTestLlm());
      setTestResult(data);
      if (data.ok && data.models?.length > 0) setModels([...data.models].sort());
    } catch (e) {
      setTestResult({ ok: false, error: e.message });
    } finally {
      setTesting(false);
    }
  }

  async function handleFetchModels() {
    setFetchingModels(true);
    try {
      const useFree = llmProvider === 'openrouter' && llmOpenrouterFreeRotate;
      const data = useFree ? await _fetchFreeModels() : await _callTestLlm(true);
      if (data.ok && data.models?.length > 0) {
        setModels([...data.models].sort());
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

  const tabs = ['Settings', 'LLM', ...(debugEnabled ? ['Debug'] : [])];

  return (
    <div style={{ overflow: "auto", flex: 1, minHeight: 0 }}>
      {consentPending && (
        <LlmConsentModal
          provider={consentPending}
          onAccept={handleConsentAccept}
          onDecline={handleConsentDecline}
        />
      )}
      {reQueuePrompt && (
        <div style={{ position: "fixed", inset: 0, zIndex: 9999, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,0.45)" }}>
          <div style={{ background: "var(--bg)", borderRadius: 12, padding: 28, maxWidth: 420, width: "90%", boxShadow: "0 8px 32px rgba(0,0,0,0.28)" }}>
            <h3 style={{ margin: "0 0 10px", fontSize: 16 }}>Switching away from Apple Intelligence</h3>
            <p style={{ margin: "0 0 18px", fontSize: 13, color: "var(--fg-mute)", lineHeight: 1.5 }}>
              Jobs processed with Apple Intelligence may have missing fields or inaccurate fit scores. Would you like to re-queue them for re-processing with your new model?
            </p>
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              <button onClick={() => handleReQueueAndSwitch("apple", reQueuePrompt)} style={{ padding: "10px 16px", borderRadius: 8, border: "1px solid var(--accent)", background: "var(--accent-bg)", color: "var(--accent)", cursor: "pointer", fontSize: 13, fontWeight: 600, textAlign: "left" }}>
                Re-queue Apple-processed jobs
                <span style={{ display: "block", fontSize: 11, fontWeight: 400, color: "var(--fg-mute)", marginTop: 2 }}>Only jobs extracted with Apple Intelligence will be re-processed.</span>
              </button>
              <button onClick={() => handleReQueueAndSwitch("all", reQueuePrompt)} style={{ padding: "10px 16px", borderRadius: 8, border: "1px solid var(--border)", background: "var(--bg-elev)", color: "var(--fg)", cursor: "pointer", fontSize: 13, textAlign: "left" }}>
                Re-queue all jobs
                <span style={{ display: "block", fontSize: 11, color: "var(--fg-mute)", marginTop: 2 }}>All previously extracted jobs will be re-processed with the new model.</span>
              </button>
              <button onClick={() => handleReQueueAndSwitch("skip", reQueuePrompt)} style={{ padding: "10px 16px", borderRadius: 8, border: "none", background: "none", color: "var(--fg-mute)", cursor: "pointer", fontSize: 13, textAlign: "left" }}>
                No thanks — switch without re-queuing
              </button>
            </div>
          </div>
        </div>
      )}
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
        {activeTab !== 'llm' && (<>
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
        </>)}

        {activeTab === 'llm' && (<>
        <Section title="LLM provider" desc="Model used for structured extraction from captured job pages.">
          <div>
            <div className="jh-label">Provider</div>
            <select
              value={llmProvider}
              onChange={e => handleProviderChange(e.target.value)}
              style={{
                width: "100%", height: 30, padding: "0 8px",
                background: "var(--bg-elev)", border: "1px solid var(--border)",
                borderRadius: "var(--r-2)", color: "var(--fg)", fontSize: 13,
              }}
            >
              {Object.entries(PROVIDER_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              {window.JH_SETTINGS?.apple_foundation_available && (
                <option value="apple">Apple Intelligence (on-device, macOS 26+)</option>
              )}
            </select>
            {llmProvider !== "apple" && (
              <div style={{ fontSize: 11, color: "var(--fg-faint)", marginTop: 4 }}>
                Not sure? From our benchmarks, <strong style={{ color: "var(--fg-mute)" }}>Gemini 3.1 Flash</strong> is a good balance of cost and accuracy to start with. See Help → Choosing a model.
              </div>
            )}
            {llmProvider === "apple" && (
              <div style={{ fontSize: 11, color: "var(--st-rejected, #c0392b)", marginTop: 4, padding: "6px 8px", background: "rgba(192,57,43,0.08)", borderRadius: "var(--r-2)", border: "1px solid var(--st-rejected, #c0392b)" }}>
                <strong>Warning:</strong> Apple Intelligence is a small on-device model. Our testing shows it produces noticeably less accurate extractions and fit scores than cloud or LM Studio models — missing fields, weaker reasoning, and inconsistent JSON output. Use it for a zero-setup first look, but plan to re-process with a stronger model before making decisions. Requires macOS 26 (Tahoe). Free, no account needed.
              </div>
            )}
          </div>

          {SHOWS_BASE_URL.has(llmProvider) && (
            <div>
              <div className="jh-label">Base URL</div>
              <div className="jh-input">
                <input value={llmBaseUrl} onChange={e => setLlmBaseUrl(e.target.value)} style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "inherit" }} />
              </div>
            </div>
          )}

          {!SHOWS_BASE_URL.has(llmProvider) && llmProvider !== "anthropic" && llmProvider !== "google" && llmProvider !== "apple" && (
            <div style={{ fontSize: 11, color: "var(--fg-faint)" }}>
              Endpoint: {llmProvider === "openai" ? "https://api.openai.com" : llmProvider === "openrouter" ? "https://openrouter.ai/api" : "(custom)"}
            </div>
          )}

          {NEEDS_API_KEY.has(llmProvider) && (
            <div>
              <div className="jh-label">API key</div>
              <div className="jh-input">
                <input
                  type="text"
                  value={llmApiKey}
                  onChange={e => setLlmApiKey(e.target.value)}
                  placeholder={llmProvider === "openai" ? "sk-…" : llmProvider === "anthropic" ? "sk-ant-…" : "API key"}
                  style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "inherit", fontFamily: "var(--font-mono)" }}
                />
              </div>
            </div>
          )}

          {llmProvider === "apple" && (
            <div style={{ fontSize: 11, color: "var(--fg-faint)" }}>
              Model: on-device (selected automatically by the OS)
            </div>
          )}

          {llmProvider !== "apple" && (() => {
            const needsKey = NEEDS_API_KEY.has(llmProvider) && !SHOWS_BASE_URL.has(llmProvider);
            const waitingForKey = needsKey && !llmApiKey;
            return (
          <div>
            <div className="jh-label">Model</div>
            <select
              value={llmModel}
              onChange={e => setLlmModel(e.target.value)}
              disabled={waitingForKey}
              size={models.length > 5 ? Math.min(models.length, 8) : 1}
              style={{
                width: "100%",
                height: models.length > 5 ? undefined : 30,
                padding: models.length > 5 ? "4px 8px" : "0 8px",
                background: "var(--bg-elev)", border: "1px solid var(--border)",
                borderRadius: "var(--r-2)", color: waitingForKey ? "var(--fg-faint)" : "var(--fg)",
                fontFamily: "var(--font-mono)", fontSize: 12,
                opacity: waitingForKey ? 0.5 : 1,
              }}
            >
              {waitingForKey && <option value="">— enter API key to load models —</option>}
              {!waitingForKey && models.length === 0 && (
                <option value={llmModel}>{llmModel || "— no models loaded —"}</option>
              )}
              {!waitingForKey && models.length > 0 && !models.includes(llmModel) && llmModel && (
                <option value={llmModel}>{llmModel} ⚠ not in list</option>
              )}
              {models.map(m => <option key={m} value={m}>{m}</option>)}
            </select>
            {!waitingForKey && (
              <div style={{ marginTop: 4 }}>
                <Btn size="sm" kind="ghost" icon={<Icon.Refresh size={11} />} onClick={handleFetchModels} disabled={fetchingModels}>
                  {fetchingModels ? "Loading models…" : models.length > 0 ? `${models.length} model${models.length !== 1 ? "s" : ""} loaded` : "Load models from server"}
                </Btn>
              </div>
            )}
          </div>
          );
          })()}

          {(() => {
            if (!contextInfo) return null;
            const { contextLength, maxObservedPromptTokens, recommendedMinTokens } = contextInfo;
            if (!contextLength) {
              return (
                <div style={{ fontSize: 11, fontFamily: 'var(--font-mono)', display: 'flex', gap: 6, alignItems: 'flex-start', color: 'var(--fg-mute)' }}>
                  <span style={{ flexShrink: 0 }}>?</span>
                  <span><span>Context window: </span><span style={{ fontWeight: 600 }}>Unknown</span>{' — provider did not report context length for this model'}</span>
                </div>
              );
            }
            const fmt = n => n >= 1000 ? `${(n / 1000).toFixed(n % 1000 === 0 ? 0 : 1)}k` : String(n);
            const isRed = maxObservedPromptTokens && contextLength < maxObservedPromptTokens;
            const isYellow = !isRed && contextLength < recommendedMinTokens;
            const color = isRed ? 'var(--st-rejected)' : isYellow ? 'var(--st-screening)' : 'var(--st-offer)';
            const symbol = isRed ? '✗' : isYellow ? '⚠' : '✓';
            const statusLabel = isRed
              ? `too small — cannot process some jobs`
              : isYellow
              ? `may truncate long job descriptions`
              : `sufficient`;
            return (
              <div style={{ fontSize: 11, fontFamily: 'var(--font-mono)', display: 'flex', gap: 6, alignItems: 'flex-start', color }}>
                <span style={{ flexShrink: 0, fontWeight: 'bold' }}>{symbol}</span>
                <span style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                  <span>
                    <span style={{ color: 'var(--fg-mute)' }}>Context window: </span>
                    <span style={{ fontWeight: 600 }}>{fmt(contextLength)} tokens</span>
                    {' — '}{statusLabel}
                  </span>
                  <span style={{ color: 'var(--fg-mute)' }}>
                    {maxObservedPromptTokens
                      ? `Largest prompt seen: ~${fmt(maxObservedPromptTokens)} tokens · `
                      : 'No jobs processed yet · '}
                    {`Recommended minimum: ${fmt(recommendedMinTokens)} tokens`}
                  </span>
                </span>
              </div>
            );
          })()}

          <Row style={{ marginTop: 4 }}>
            <Btn size="sm" kind="accent" icon={<Icon.Check size={11} />} onClick={handleTestLlm} disabled={testing}>
              {testing ? "Testing…" : "Test connection"}
            </Btn>
            {testResult && (
              <span style={{ fontSize: 12, display: "inline-flex", flexDirection: "column", gap: 4 }}>
                {(() => {
                  const isApple = llmProvider === "apple";
                  const noModels = testResult.ok && !isApple && (testResult.models?.length || 0) === 0;
                  const connOk = testResult.ok && !noModels;
                  const connColor = connOk ? "var(--st-offer)" : "var(--st-rejected)";
                  const providerName = PROVIDER_LABELS[llmProvider] || llmProvider;
                  const connText = !testResult.ok ? testResult.error
                    : isApple ? "Apple Intelligence · on-device"
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
          {llmProvider === "openrouter" && (
            <div style={{ border: "1px solid var(--border)", borderRadius: "var(--r-2)", padding: "10px 12px", background: "var(--bg-elev)" }}>
              <label style={{ display: "flex", alignItems: "flex-start", gap: 8, cursor: "pointer" }}>
                <input type="checkbox" checked={llmOpenrouterFreeRotate} onChange={e => setLlmOpenrouterFreeRotate(e.target.checked)} style={{ marginTop: 2 }} />
                <span>
                  <span style={{ color: "var(--fg-strong)", fontWeight: 600, fontSize: 13 }}>Use free models (rotate)</span>
                  <span style={{ display: "block", fontSize: 11.5, color: "var(--fg-mute)", marginTop: 3, lineHeight: 1.5 }}>
                    Round-robins requests across OpenRouter's free models that support structured output, with automatic failover. Ignores the model picked above and costs $0.
                  </span>
                </span>
              </label>
              {llmOpenrouterFreeRotate && (
                <div style={{ fontSize: 11, color: "var(--st-screening)", marginTop: 8, lineHeight: 1.5, display: "flex", gap: 6, alignItems: "flex-start" }}>
                  <span style={{ flexShrink: 0, fontWeight: "bold" }}>⚠</span>
                  <span>This sends your job descriptions and resumes to a wide range of third-party hosting providers and models based in various countries (e.g. US, China). Only enable if you're comfortable with that.</span>
                </div>
              )}
            </div>
          )}
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

        <Section title="Cost estimate" desc="Estimate what processing all your jobs would cost on a paid provider. Local LLMs are free — set both prices to 0.">
          <CostEstimate priceInput={llmPriceInput} setPriceInput={setLlmPriceInput} priceOutput={llmPriceOutput} setPriceOutput={setLlmPriceOutput} />
        </Section>
        </>)}

        {activeTab !== 'llm' && (<>
        <Section title="Resumes" desc="Upload one or more resume PDFs (or paste text). Each job is scored 0-100 against every active resume so you can see which resume fits best.">
          <ResumeManager />
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
        </>)}
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

      <Section title="Token usage" desc="Actual prompt sizes from succeeded LLM attempts vs. configured caps. Use this to right-size your model's loaded context window.">
        {(() => {
          const p = stats?.promptStats;
          const j = stats?.jdStats;
          const caps = stats?.tokenCaps;
          const fmtTok = chars => chars == null ? '—' : `~${Math.ceil(chars / 4).toLocaleString()} tokens (${Math.round(chars / 1024 * 10) / 10} KB)`;
          const fmtMs = ms => ms == null ? '—' : ms >= 60000 ? `${(ms / 60000).toFixed(1)}m` : `${(ms / 1000).toFixed(1)}s`;
          const rows = [
            { label: 'Attempts (succeeded)', val: p?.attempts == null ? '—' : p.attempts.toLocaleString() },
            { label: 'Largest prompt sent', val: fmtTok(p?.max_prompt_chars) },
            { label: 'Average prompt sent', val: fmtTok(p?.avg_prompt_chars) },
            { label: 'Largest JD captured', val: fmtTok(j?.max_jd_chars) },
            { label: 'Average JD captured', val: fmtTok(j?.avg_jd_chars) },
            { label: 'JD truncation cap', val: fmtTok(caps?.maxDescriptionChars) },
            { label: 'Resume truncation cap', val: fmtTok(caps?.maxResumeChars) },
            { label: 'Theoretical max prompt', val: fmtTok((caps?.maxDescriptionChars ?? 0) + (caps?.maxResumeChars ?? 0)) },
            { label: 'Avg processing time', val: fmtMs(p?.avg_duration_ms) },
            { label: 'Longest processing time', val: fmtMs(p?.max_duration_ms) },
          ];
          return (
            <div style={{ maxWidth: 480 }}>
              {rows.map(({ label, val }) => (
                <div key={label} style={{ display: 'flex', justifyContent: 'space-between', padding: '3px 0', fontSize: 13, borderBottom: '1px solid var(--border)' }}>
                  <span style={{ color: 'var(--fg-mute)' }}>{label}</span>
                  <span style={{ fontFamily: 'var(--font-mono)', fontSize: 12 }}>{val}</span>
                </div>
              ))}
            </div>
          );
        })()}
      </Section>

      <Section title="Logging" desc="Controls verbosity of LLM attempt logging to the debug log file.">
        <Row>
          <Btn size="sm" variant={verbose ? 'primary' : undefined} onClick={onToggleVerbose}>
            {verbose ? 'Full (verbose)' : 'Errors only'}
          </Btn>
          <span style={{ fontSize: 12, color: 'var(--fg-mute)' }}>llm_debug_level = {llmDebugLevel}</span>
        </Row>
      </Section>

      <Section title="Onboarding" desc="Re-open the setup wizard.">
        <Row>
          <Btn size="sm" onClick={() => {
            localStorage.removeItem(window.WELCOME_KEY || 'jh.welcome_dismissed');
            localStorage.removeItem('jobhunt.force_first_run');
            window.JH_OPEN_ONBOARDING?.();
          }}>Open setup wizard</Btn>
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

// ------------------------------------------------------------------
// Resume manager (multiple resumes, client-side PDF text extraction)
// ------------------------------------------------------------------

let _pdfjsPromise = null;
function loadPdfJs() {
  if (window.pdfjsLib) {
    window.pdfjsLib.GlobalWorkerOptions.workerSrc = "/static/vendor/pdfjs/pdf.worker.min.js";
    return Promise.resolve(window.pdfjsLib);
  }
  if (_pdfjsPromise) return _pdfjsPromise;
  _pdfjsPromise = new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "/static/vendor/pdfjs/pdf.min.js";
    s.onload = () => {
      if (window.pdfjsLib) {
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = "/static/vendor/pdfjs/pdf.worker.min.js";
        resolve(window.pdfjsLib);
      } else {
        reject(new Error("pdf.js failed to load"));
      }
    };
    s.onerror = () => reject(new Error("pdf.js failed to load"));
    document.head.appendChild(s);
  });
  return _pdfjsPromise;
}

async function extractPdfText(file) {
  const pdfjsLib = await loadPdfJs();
  const buf = await file.arrayBuffer();
  const pdf = await pdfjsLib.getDocument({ data: new Uint8Array(buf) }).promise;
  const pages = [];
  for (let i = 1; i <= pdf.numPages; i++) {
    const page = await pdf.getPage(i);
    const content = await page.getTextContent();
    pages.push(content.items.map(it => it.str).join(" "));
  }
  return pages.join("\n").replace(/[ \t]+/g, " ").trim();
}

function ResumeManager() {
  const [resumes, setResumes] = React.useState(() => window.JH_RESUMES || []);
  const [busy, setBusy] = React.useState(false);
  const [status, setStatus] = React.useState(null);
  const [editing, setEditing] = React.useState(null); // resume id whose text box is open
  const [draftText, setDraftText] = React.useState("");
  const [pasteOpen, setPasteOpen] = React.useState(false);
  const [pasteName, setPasteName] = React.useState("");
  const [pasteText, setPasteText] = React.useState("");
  const fileRef = React.useRef(null);

  async function loadResumes() {
    try {
      const res = await window.JH_API.listResumes();
      setResumes(res.resumes || []);
    } catch (e) {
      setStatus({ kind: "error", text: e.message });
    }
  }

  async function onFiles(e) {
    const files = Array.from(e.target.files || []);
    if (fileRef.current) fileRef.current.value = "";
    if (!files.length) return;
    setBusy(true);
    let added = 0, queued = 0, warned = 0;
    for (const file of files) {
      try {
        setStatus({ kind: "saving", text: `Reading ${file.name}…` });
        const text = await extractPdfText(file);
        if (!text.trim()) {
          warned++;
          setStatus({ kind: "error", text: `${file.name}: no text found (scanned/image PDF). Use "Paste text" instead.` });
          continue;
        }
        const name = file.name.replace(/\.pdf$/i, "");
        const res = await window.JH_API.addResume({ name, filename: file.name, text });
        added++;
        queued += res?.queued_jobs || 0;
      } catch (err) {
        setStatus({ kind: "error", text: `${file.name}: ${err.message}` });
      }
    }
    await loadResumes();
    setBusy(false);
    if (added) {
      setStatus({ kind: "success", text: `Added ${added} resume${added > 1 ? "s" : ""}${queued ? ` · scoring ${queued} job${queued > 1 ? "s" : ""}` : ""}${warned ? ` · ${warned} skipped` : ""}` });
    }
  }

  async function savePasted() {
    if (!pasteText.trim()) return;
    setBusy(true);
    try {
      const res = await window.JH_API.addResume({ name: pasteName.trim() || "Pasted resume", text: pasteText });
      await loadResumes();
      setPasteOpen(false); setPasteName(""); setPasteText("");
      setStatus({ kind: "success", text: `Added resume${res?.queued_jobs ? ` · scoring ${res.queued_jobs} jobs` : ""}` });
    } catch (e) {
      setStatus({ kind: "error", text: e.message });
    } finally {
      setBusy(false);
    }
  }

  async function rename(id, name) {
    try { await window.JH_API.updateResume(id, { name }); await loadResumes(); }
    catch (e) { setStatus({ kind: "error", text: e.message }); }
  }
  async function toggleActive(id, active) {
    try { await window.JH_API.updateResume(id, { active }); await loadResumes(); }
    catch (e) { setStatus({ kind: "error", text: e.message }); }
  }
  async function saveText(id) {
    setBusy(true);
    try { await window.JH_API.updateResume(id, { text: draftText }); setEditing(null); await loadResumes(); }
    catch (e) { setStatus({ kind: "error", text: e.message }); }
    finally { setBusy(false); }
  }
  async function openEditor(id) {
    const full = await window.JH_API.api(`/api/resumes/${id}`);
    setDraftText(full?.text || "");
    setEditing(id);
  }
  async function remove(id, name) {
    if (!window.confirm(`Delete resume "${name}"? Its fit scores will be removed.`)) return;
    try { await window.JH_API.deleteResume(id); await loadResumes(); setStatus({ kind: "success", text: "Resume deleted" }); }
    catch (e) { setStatus({ kind: "error", text: e.message }); }
  }

  return (
    <div>
      <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        <input ref={fileRef} type="file" accept=".pdf" multiple onChange={onFiles} style={{ display: "none" }} />
        <Btn size="sm" kind="accent" disabled={busy} icon={<Icon.Plus size={12} />} onClick={() => fileRef.current?.click()}>
          {busy ? "Working…" : "Upload PDFs"}
        </Btn>
        <Btn size="sm" disabled={busy} onClick={() => setPasteOpen(v => !v)}>Paste text</Btn>
        {status && (
          <span style={{ fontSize: 11.5, color: status.kind === "error" ? "var(--st-rejected)" : status.kind === "success" ? "var(--st-offer)" : "var(--fg-mute)" }}>
            {status.text}
          </span>
        )}
      </div>

      {pasteOpen && (
        <div style={{ marginTop: 10, display: "flex", flexDirection: "column", gap: 6 }}>
          <input className="jh-input" style={{ padding: "0 8px", height: 30 }} placeholder="Resume name" value={pasteName} onChange={e => setPasteName(e.target.value)} />
          <textarea value={pasteText} onChange={e => setPasteText(e.target.value)} placeholder="Paste resume text…" rows={8}
            style={{ width: "100%", padding: "8px 10px", background: "var(--bg-elev)", border: "1px solid var(--border)", borderRadius: "var(--r-2)", color: "var(--fg)", fontFamily: "var(--font-mono)", fontSize: 12, resize: "vertical" }} />
          <div><Btn size="sm" kind="accent" disabled={busy || !pasteText.trim()} onClick={savePasted}>Save resume</Btn></div>
        </div>
      )}

      <div style={{ marginTop: 12, display: "flex", flexDirection: "column", gap: 8 }}>
        {resumes.length === 0 && (
          <div style={{ fontSize: 12, color: "var(--fg-faint)" }}>No resumes yet. Upload a PDF to enable fit scoring.</div>
        )}
        {resumes.map(r => (
          <div key={r.id} style={{ border: "1px solid var(--border)", borderRadius: "var(--r-2)", padding: "8px 10px", background: "var(--bg-elev)" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <input
                defaultValue={r.name}
                onBlur={e => { const v = e.target.value.trim(); if (v && v !== r.name) rename(r.id, v); }}
                style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "var(--fg)", fontSize: 13, fontWeight: 600 }}
              />
              <label style={{ fontSize: 11, color: "var(--fg-mute)", display: "inline-flex", alignItems: "center", gap: 4 }} title="Score new jobs against this resume">
                <input type="checkbox" checked={!!r.active} onChange={e => toggleActive(r.id, e.target.checked)} /> active
              </label>
              <Btn size="sm" onClick={() => (editing === r.id ? setEditing(null) : openEditor(r.id))}>{editing === r.id ? "Close" : "Edit text"}</Btn>
              <Btn size="sm" kind="ghost" icon={<Icon.Trash size={12} />} onClick={() => remove(r.id, r.name)} />
            </div>
            <div style={{ fontSize: 11, color: "var(--fg-faint)", fontFamily: "var(--font-mono)", marginTop: 2 }}>
              {r.filename ? `${r.filename} · ` : ""}{r.char_count} chars
            </div>
            {editing === r.id && (
              <div style={{ marginTop: 8 }}>
                <textarea value={draftText} onChange={e => setDraftText(e.target.value)} rows={12}
                  style={{ width: "100%", padding: "8px 10px", background: "var(--bg)", border: "1px solid var(--border)", borderRadius: "var(--r-2)", color: "var(--fg)", fontFamily: "var(--font-mono)", fontSize: 12, resize: "vertical", lineHeight: 1.45 }} />
                <div style={{ marginTop: 6 }}><Btn size="sm" kind="accent" disabled={busy} onClick={() => saveText(r.id)}>Save text</Btn></div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// ------------------------------------------------------------------
// LLM cost estimate
// ------------------------------------------------------------------

function fmtUSD(n) {
  if (!isFinite(n) || n === 0) return "$0.00";
  if (n < 0.01) return "$" + n.toFixed(4);
  if (n < 1) return "$" + n.toFixed(3);
  return "$" + n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
function fmtNum(n) { return (Math.round(n) || 0).toLocaleString(); }

function CostEstimate({ priceInput, setPriceInput, priceOutput, setPriceOutput }) {
  const [cost, setCost] = React.useState(null);
  const [costErr, setCostErr] = React.useState(false);
  const [models, setModels] = React.useState(null); // null=unloaded, []=loaded/empty
  const [loadingModels, setLoadingModels] = React.useState(false);

  React.useEffect(() => {
    fetch("/api/llm-cost").then(r => r.json()).then(setCost).catch(() => setCostErr(true));
  }, []);

  async function loadModels() {
    if (models || loadingModels) return;
    setLoadingModels(true);
    try {
      const r = await fetch("/api/llm-pricing");
      const j = await r.json();
      setModels(j.models || []);
    } catch {
      setModels([]);
    } finally {
      setLoadingModels(false);
    }
  }

  function onPickModel(e) {
    const id = e.target.value;
    const m = (models || []).find(x => x.id === id);
    if (m) {
      setPriceInput(String(m.input_per_1m));
      setPriceOutput(String(m.output_per_1m));
    }
  }

  const pin = parseFloat(priceInput) || 0;
  const pout = parseFloat(priceOutput) || 0;
  const costOf = (g) => g ? (g.input_tokens / 1e6) * pin + (g.output_tokens / 1e6) * pout : 0;

  const priceField = (label, value, set) => (
    <div style={{ flex: 1 }}>
      <div className="jh-label">{label}</div>
      <div className="jh-input" style={{ paddingRight: 8 }}>
        <span style={{ color: "var(--fg-mute)" }}>$</span>
        <input type="number" min="0" step="0.01" value={value} onChange={e => set(e.target.value)}
          style={{ flex: 1, background: "transparent", border: "none", outline: "none", color: "inherit", fontFamily: "var(--font-mono)" }} />
        <span style={{ color: "var(--fg-mute)", fontSize: 11 }}>/ 1M tokens</span>
      </div>
    </div>
  );

  return (
    <div>
      <div className="jh-row" style={{ gap: 16 }}>
        {priceField("Input price", priceInput, setPriceInput)}
        {priceField("Output price", priceOutput, setPriceOutput)}
      </div>

      <div style={{ marginTop: 8 }}>
        <div className="jh-label">Look up a provider's price</div>
        <input list="jh-or-models" placeholder="Search a model, e.g. google/gemini-2.5-flash" onFocus={loadModels} onChange={onPickModel}
          style={{ width: "100%", height: 30, padding: "0 8px", background: "var(--bg-elev)", border: "1px solid var(--border)", borderRadius: "var(--r-2)", color: "var(--fg)", fontFamily: "var(--font-mono)", fontSize: 12 }} />
        <datalist id="jh-or-models">
          {(models || []).map(m => <option key={m.id} value={m.id}>{m.name} — ${m.input_per_1m}/${m.output_per_1m} per 1M</option>)}
        </datalist>
        <div style={{ fontSize: 11, color: "var(--fg-faint)", marginTop: 4 }}>
          {loadingModels ? "Loading prices from OpenRouter…"
            : models && models.length ? `${models.length} models from OpenRouter — picking one fills the prices above (edit freely; buying direct may differ).`
            : models && !models.length ? "Couldn't reach OpenRouter — enter prices manually from the provider's pricing page."
            : "Live prices via OpenRouter; or type prices in manually."}
        </div>
      </div>

      {costErr && <div style={{ marginTop: 12, fontSize: 12, color: "var(--st-rejected)" }}>Couldn't load cost data.</div>}
      {cost && !cost.has_data && (
        <div style={{ marginTop: 12, fontSize: 12.5, color: "var(--fg-mute)" }}>
          No jobs captured yet. Set prices here to estimate future cost — and revisit this to gauge your savings vs. running locally as you add jobs.
        </div>
      )}

      {cost && cost.has_data && (() => {
        const allExt = costOf(cost.all.extraction);
        const allFit = costOf(cost.all.fit);
        const allTotal = allExt + allFit;
        const remTotal = costOf(cost.remaining.extraction) + costOf(cost.remaining.fit);
        const perJob = costOf(cost.per_job.extraction) + costOf(cost.per_job.fit);
        const allTokens = cost.all.extraction.input_tokens + cost.all.extraction.output_tokens + cost.all.fit.input_tokens + cost.all.fit.output_tokens;
        const row = (label, value, opts = {}) => (
          <div style={{ display: "flex", justifyContent: "space-between", padding: "5px 0", borderTop: opts.divider ? "1px solid var(--border)" : "none", fontSize: opts.strong ? 13 : 12.5 }}>
            <span style={{ color: opts.strong ? "var(--fg-strong)" : "var(--fg-mute)", fontWeight: opts.strong ? 600 : 400 }}>{label}</span>
            <span style={{ color: opts.strong ? "var(--fg)" : "var(--fg-mute)", fontWeight: opts.strong ? 700 : 400, fontFamily: "var(--font-mono)" }}>{value}</span>
          </div>
        );
        return (
          <div style={{ marginTop: 14 }}>
            <div style={{ fontSize: 11.5, color: "var(--fg-faint)", marginBottom: 6 }}>
              {fmtNum(cost.jobs_total)} jobs · {cost.resumes_active} active resume{cost.resumes_active !== 1 ? "s" : ""} · {fmtNum(cost.fit_pairs_total)} fit evaluations · ~{fmtNum(allTokens)} tokens total
            </div>
            {row("Extraction — all jobs", fmtUSD(allExt))}
            {row("Fit scoring — all jobs", fmtUSD(allFit))}
            {row("Process everything (upfront)", fmtUSD(allTotal), { strong: true, divider: true })}
            {row(`Still to do (${fmtNum(cost.jobs_total - cost.jobs_extracted)} jobs, ${fmtNum(cost.fit_pairs_total - cost.fit_pairs_done)} pairs)`, fmtUSD(remTotal), { divider: true })}
            {row("Average per job", fmtUSD(perJob), { divider: true })}
            <div style={{ fontSize: 11, color: "var(--fg-faint)", marginTop: 8, lineHeight: 1.5 }}>
              Rough estimate: ~{cost.chars_per_token} chars/token, prompt overhead included, output sizes from your stored results. Local LLMs cost $0. Actual provider billing will vary.
            </div>
          </div>
        );
      })()}
    </div>
  );
}

Object.assign(window, { SettingsPage });
