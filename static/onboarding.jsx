// Jobhunt — Onboarding wizard

const OB_PROVIDERS_BASE = [
  {
    id: 'lmstudio',
    emoji: '🖥️',
    label: 'LM Studio',
    tagline: 'Free & fully private',
    desc: 'AI runs locally on your Mac. No data leaves your machine, no cost per job. Requires downloading LM Studio and a model (~4–8 GB RAM).',
    needsBaseUrl: true,
    needsApiKey: false,
    defaultBase: 'http://127.0.0.1:1234',
  },
  {
    id: 'openai',
    emoji: '⚡',
    label: 'OpenAI',
    tagline: 'Easiest setup',
    desc: 'GPT-4o gives excellent extraction quality. About $0.01–0.05 per job. Requires an API key. Job content is sent to OpenAI.',
    needsBaseUrl: false,
    needsApiKey: true,
  },
  {
    id: 'anthropic',
    emoji: '✨',
    label: 'Anthropic',
    tagline: 'Highest quality',
    desc: 'Claude Sonnet gives the best extraction results. About $0.01–0.05 per job. Requires an API key.',
    needsBaseUrl: false,
    needsApiKey: true,
  },
  {
    id: 'google',
    emoji: '🆓',
    label: 'Google Gemini',
    tagline: 'Free tier available',
    desc: 'Gemini 2.5 Flash is fast with a generous free tier. Requires a Google API key. Job content is sent to Google.',
    needsBaseUrl: false,
    needsApiKey: true,
  },
];

const OB_PROVIDER_APPLE = {
  id: 'apple',
  emoji: '🍎',
  label: 'Apple Intelligence',
  tagline: 'Zero setup — try it now',
  desc: 'Runs on-device using macOS 26 built-in AI. No account, no cost, no data sent anywhere. Good for a quick first look — but known to miss details in job descriptions. Plan to switch to a stronger model later.',
  needsBaseUrl: false,
  needsApiKey: false,
  warning: true,
};

function getOBProviders() {
  if (window.JH_SETTINGS?.apple_foundation_available) {
    return [OB_PROVIDER_APPLE, ...OB_PROVIDERS_BASE];
  }
  return OB_PROVIDERS_BASE;
}

const API_KEY_URLS = {
  openai: { label: 'Get API key', url: 'https://platform.openai.com/api-keys' },
  anthropic: { label: 'Get API key', url: 'https://console.anthropic.com/account/keys' },
  google: { label: 'Get API key', url: 'https://aistudio.google.com/app/apikey' },
  openrouter: { label: 'Get API key', url: 'https://openrouter.ai/keys' },
};
const LM_STUDIO_URL = 'https://lmstudio.ai/download';

const TOTAL_STEPS = 6;

function StepDots({ step }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 6, marginBottom: 32 }}>
      {Array.from({ length: TOTAL_STEPS }, (_, i) => (
        <div key={i} style={{
          height: 6,
          width: i === step ? 20 : 6,
          borderRadius: 3,
          background: i <= step ? 'var(--accent)' : 'var(--border-strong)',
          transition: 'width 0.2s, background 0.2s',
        }} />
      ))}
    </div>
  );
}

function WizardNav({ step, onBack, onContinue, onSkip, continueLabel = 'Continue', continueDisabled = false, saving = false }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 32, paddingTop: 20, borderTop: '1px solid var(--border)' }}>
      <div>
        {step > 0 && (
          <button onClick={onBack} style={{ background: 'none', border: 'none', color: 'var(--fg-mute)', cursor: 'pointer', fontSize: 13, padding: '6px 0' }}>
            ← Back
          </button>
        )}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        {onSkip && (
          <button onClick={onSkip} style={{ background: 'none', border: 'none', color: 'var(--fg-mute)', cursor: 'pointer', fontSize: 13, padding: '6px 8px' }}>
            Skip
          </button>
        )}
        <Btn kind="accent" onClick={onContinue} disabled={continueDisabled || saving}>
          {saving ? 'Saving…' : continueLabel}
        </Btn>
      </div>
    </div>
  );
}

// Step 0: Welcome
function StepWelcome({ onNext, onDemo }) {
  const features = [
    { emoji: '📋', title: 'Capture any job posting', desc: 'One click in Chrome saves a job to your tracker. Or paste a URL and Jobhunt fetches it for you.' },
    { emoji: '🤖', title: 'AI extraction', desc: 'Automatically pulls out title, company, salary, location, and work mode — no copy-pasting.' },
    { emoji: '📊', title: 'Fit scoring', desc: 'Every job is scored 0–100 against your resume so you can prioritize what to apply to.' },
    { emoji: '🔁', title: 'Pipeline tracking', desc: 'Move jobs through Saved → Applied → Interview → Offer. See your whole search at a glance.' },
    { emoji: '🔍', title: 'Availability checks', desc: 'Jobhunt periodically checks if postings are still live, so you\'re not chasing expired listings.' },
    { emoji: '🗄️', title: 'Fully local', desc: 'Everything lives in a SQLite database on your Mac. No account, no cloud, no subscription.' },
  ];

  return (
    <div>
      <div style={{ textAlign: 'center', marginBottom: 24 }}>
        <div style={{ fontSize: 48, marginBottom: 12 }}>🎯</div>
        <h2 style={{ margin: '0 0 10px', fontSize: 24, fontWeight: 700 }}>Stop losing track of jobs</h2>
        <p style={{ margin: 0, color: 'var(--fg-mute)', lineHeight: 1.65, maxWidth: 400, marginInline: 'auto' }}>
          Jobhunt is a local-first job tracker that uses AI to do the tedious work — so you can focus on applying and interviewing.
        </p>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginBottom: 24 }}>
        {features.map(f => (
          <div key={f.title} style={{ padding: '12px 14px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-elev-2)' }}>
            <div style={{ fontSize: 20, marginBottom: 6 }}>{f.emoji}</div>
            <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 3 }}>{f.title}</div>
            <div style={{ fontSize: 12, color: 'var(--fg-mute)', lineHeight: 1.45 }}>{f.desc}</div>
          </div>
        ))}
      </div>

      <div style={{ padding: '12px 16px', borderRadius: 8, background: 'var(--bg-elev-2)', border: '1px solid var(--border)', fontSize: 13, color: 'var(--fg-mute)', lineHeight: 1.5 }}>
        <strong style={{ color: 'var(--fg)' }}>When fully set up:</strong> browse any job board → click the extension → job is captured, extracted, and scored automatically within seconds. Your whole search lives in one place.
      </div>

      <div style={{ marginTop: 16, padding: '12px 16px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-elev-2)', display: 'flex', alignItems: 'center', gap: 12 }}>
        <span style={{ fontSize: 20 }}>🎮</span>
        <div style={{ flex: 1 }}>
          <div style={{ fontWeight: 600, fontSize: 13 }}>Just exploring?</div>
          <div style={{ fontSize: 12, color: 'var(--fg-mute)', lineHeight: 1.4 }}>Load sample data to see the app with realistic jobs, statuses, and pipeline stages — no setup required.</div>
        </div>
        <button onClick={onDemo} style={{ flexShrink: 0, padding: '6px 14px', borderRadius: 6, border: '1px solid var(--accent)', background: 'transparent', color: 'var(--accent)', fontSize: 13, fontWeight: 500, cursor: 'pointer' }}>
          Try demo →
        </button>
      </div>

      <WizardNav step={0} onContinue={onNext} continueLabel="Get started →" />
    </div>
  );
}

// Step 1: Chrome Extension
function StepExtension({ onNext, onBack }) {
  const step = { fontSize: 13, padding: '7px 0', borderBottom: '1px solid var(--border)', display: 'flex', gap: 10, alignItems: 'flex-start' };
  const num = { flexShrink: 0, width: 20, height: 20, borderRadius: 10, background: 'var(--accent)', color: '#fff', fontSize: 11, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 1 };
  const code = { fontFamily: 'var(--font-mono)', fontSize: 12, background: 'var(--bg-elev-2)', border: '1px solid var(--border)', borderRadius: 4, padding: '1px 5px' };

  return (
    <div>
      <div style={{ fontSize: 40, marginBottom: 12, textAlign: 'center' }}>🧩</div>
      <h2 style={{ margin: '0 0 8px', fontSize: 22, fontWeight: 700, textAlign: 'center' }}>Chrome extension</h2>
      <p style={{ margin: '0 0 20px', color: 'var(--fg-mute)', textAlign: 'center', lineHeight: 1.6 }}>
        The extension captures any job posting with one click — the fastest way to get jobs into Jobhunt.
      </p>

      {/* Chrome Web Store */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 16px', borderRadius: 8, background: 'var(--accent-bg)', border: '2px solid var(--accent)', marginBottom: 16 }}>
        <span style={{ fontSize: 28, flexShrink: 0 }}>🏪</span>
        <div style={{ flex: 1 }}>
          <div style={{ fontWeight: 700, fontSize: 14, color: 'var(--fg)', marginBottom: 4 }}>Available on the Chrome Web Store</div>
          <div style={{ fontSize: 12, color: 'var(--fg-mute)', marginBottom: 10, lineHeight: 1.4 }}>One-click install — no developer mode or manual setup needed.</div>
          <a
            href="https://chromewebstore.google.com/detail/jobhunt-capture/jekcbebhfeidkpapienoflbcaeeknlch"
            target="_blank"
            rel="noopener noreferrer"
            style={{ display: 'inline-block', padding: '7px 16px', borderRadius: 6, background: 'var(--accent)', color: '#fff', fontSize: 13, fontWeight: 600, textDecoration: 'none' }}
          >
            → Install Jobhunt Capture
          </a>
        </div>
      </div>

      <div style={{ padding: '14px 16px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-elev)', marginBottom: 16 }}>
        <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 10 }}>After installing</div>
        <div style={step}>
          <div style={num}>1</div>
          <div>Pin the <strong>Jobhunt Capture</strong> icon to your Chrome toolbar</div>
        </div>
        <div style={{ ...step, borderBottom: 'none', paddingBottom: 0 }}>
          <div style={num}>2</div>
          <div>Browse to any job posting and click the icon to capture it — done</div>
        </div>
      </div>

      {/* Without extension */}
      <div style={{ padding: '10px 14px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-elev-2)', fontSize: 12, color: 'var(--fg-mute)', lineHeight: 1.5 }}>
        <strong style={{ color: 'var(--fg)' }}>Don't want to install it yet?</strong> Use <strong>Add Job URL</strong> in the toolbar — Jobhunt fetches the page for you. Works for most public job boards.
      </div>

      <WizardNav step={1} onBack={onBack} onContinue={onNext} continueLabel="Got it, continue" />
    </div>
  );
}

// Step 2: AI Provider
function StepAI({ provider, setProvider, apiKey, setApiKey, baseUrl, setBaseUrl, model, setModel, onNext, onBack, onSkip }) {
  const [testResult, setTestResult] = React.useState(null);
  const [testing, setTesting] = React.useState(false);
  const [fetchedModels, setFetchedModels] = React.useState([]);
  const [fetchingModels, setFetchingModels] = React.useState(false);
  const OB_PROVIDERS = getOBProviders();
  const info = OB_PROVIDERS.find(p => p.id === provider) || OB_PROVIDERS[0];

  async function fetchModels() {
    setFetchingModels(true);
    try {
      const res = await fetch('/api/settings/test-llm', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ provider, api_key: apiKey, base_url: baseUrl, quick: true }),
      });
      const data = await res.json();
      if (data.models && Array.isArray(data.models) && data.models.length > 0) {
        setFetchedModels(data.models);
        if (!model || !data.models.includes(model)) {
          setModel(data.models[0]);
        }
      }
    } catch (e) {
      // silently ignore fetch errors
    } finally {
      setFetchingModels(false);
    }
  }

  // Auto-fetch models for LM Studio (no key needed)
  React.useEffect(() => {
    if (provider === 'lmstudio') {
      setFetchedModels([]);
      fetchModels();
    } else {
      setFetchedModels([]);
    }
  }, [provider]); // eslint-disable-line react-hooks/exhaustive-deps

  // Debounced fetch when API key changes (for cloud providers)
  React.useEffect(() => {
    if (provider === 'lmstudio' || apiKey.length <= 10) return;
    const timer = setTimeout(() => fetchModels(), 800);
    return () => clearTimeout(timer);
  }, [apiKey]); // eslint-disable-line react-hooks/exhaustive-deps

  async function test() {
    setTesting(true);
    setTestResult(null);
    try {
      const res = await fetch('/api/settings/test-llm', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ provider, api_key: apiKey, model, base_url: baseUrl, quick: true }),
      });
      const data = await res.json();
      setTestResult(data);
      if (data.models && Array.isArray(data.models) && data.models.length > 0) {
        setFetchedModels(data.models);
        if (!model || !data.models.includes(model)) {
          setModel(data.models[0]);
        }
      }
    } catch (e) {
      setTestResult({ ok: false, error: e.message });
    } finally {
      setTesting(false);
    }
  }

  const apiKeyInfo = API_KEY_URLS[provider];

  return (
    <div>
      <h2 style={{ margin: '0 0 8px', fontSize: 22, fontWeight: 700 }}>Set up AI extraction</h2>
      <p style={{ margin: '0 0 20px', color: 'var(--fg-mute)', lineHeight: 1.6 }}>
        Jobhunt uses AI to extract structured data — title, company, salary, location — from job postings, and to score each job against your resume.
      </p>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginBottom: 20 }}>
        {OB_PROVIDERS.map(p => {
          const active = provider === p.id;
          return (
            <button key={p.id} onClick={() => { setProvider(p.id); setTestResult(null); if (p.needsBaseUrl) setBaseUrl(p.defaultBase || baseUrl); }} style={{
              padding: '12px 14px', borderRadius: 8, textAlign: 'left', cursor: 'pointer',
              border: active ? '2px solid var(--accent)' : '1px solid var(--border)',
              background: active ? 'var(--accent-bg)' : 'var(--bg)',
              outline: 'none',
            }}>
              <div style={{ fontSize: 20, marginBottom: 4 }}>{p.emoji}</div>
              <div style={{ fontWeight: 600, fontSize: 13, color: 'var(--fg)' }}>{p.label}</div>
              <div style={{ fontSize: 11, color: 'var(--accent)', marginBottom: 4 }}>{p.tagline}</div>
              <div style={{ fontSize: 11, color: 'var(--fg-mute)', lineHeight: 1.4 }}>{p.desc}</div>
            </button>
          );
        })}
      </div>

      {/* Provider config */}
      <div style={{ padding: '14px 16px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-elev)', marginBottom: 12 }}>
        {provider === 'apple' ? (
          <div>
            <div style={{ fontSize: 12, color: 'var(--st-rejected, #c0392b)', padding: '8px 10px', borderRadius: 6, background: 'rgba(192,57,43,0.08)', border: '1px solid var(--st-rejected, #c0392b)', marginBottom: 10, lineHeight: 1.5 }}>
              <strong>Heads up:</strong> Apple Intelligence is a small on-device model — great for getting started instantly, but known to miss details in job descriptions and produce weaker fit scores. Plan to switch to a cloud or LM Studio model once you're set up.
            </div>
            <div style={{ fontSize: 12, color: 'var(--fg-mute)', marginBottom: 10 }}>Model: selected automatically by macOS — no configuration needed.</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <Btn size="sm" onClick={test} disabled={testing}>{testing ? 'Testing…' : 'Test connection'}</Btn>
              {testResult && (
                <span style={{ fontSize: 12, color: testResult.ok ? 'var(--st-offer)' : 'var(--st-rejected)' }}>
                  {testResult.ok ? '✓ Ready' : `✗ ${testResult.error || 'Failed'}`}
                </span>
              )}
            </div>
          </div>
        ) : (
          <div>
            {info.needsBaseUrl && (
              <div style={{ marginBottom: 10 }}>
                <label style={{ fontSize: 12, color: 'var(--fg-mute)', display: 'block', marginBottom: 4 }}>Server URL</label>
                <input value={baseUrl} onChange={e => setBaseUrl(e.target.value)} placeholder="http://127.0.0.1:1234"
                  style={{ width: '100%', padding: '7px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--fg)', fontSize: 13, boxSizing: 'border-box' }} />
                <div style={{ marginTop: 4, fontSize: 11, color: 'var(--fg-mute)' }}>
                  <a href={LM_STUDIO_URL} target="_blank" rel="noopener noreferrer" style={{ color: 'var(--accent)' }}>→ Download LM Studio</a>
                </div>
              </div>
            )}
            {info.needsApiKey && (
              <div style={{ marginBottom: 10 }}>
                <label style={{ fontSize: 12, color: 'var(--fg-mute)', display: 'block', marginBottom: 4 }}>API key</label>
                <input type="password" value={apiKey} onChange={e => setApiKey(e.target.value)}
                  placeholder={provider === 'openai' ? 'sk-…' : provider === 'anthropic' ? 'sk-ant-…' : 'API key'}
                  style={{ width: '100%', padding: '7px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--fg)', fontSize: 13, boxSizing: 'border-box' }} />
                {apiKeyInfo && (
                  <div style={{ marginTop: 4, fontSize: 11, color: 'var(--fg-mute)' }}>
                    <a href={apiKeyInfo.url} target="_blank" rel="noopener noreferrer" style={{ color: 'var(--accent)' }}>→ {apiKeyInfo.label}</a>
                  </div>
                )}
              </div>
            )}
            <div style={{ marginBottom: 10 }}>
              <label style={{ fontSize: 12, color: 'var(--fg-mute)', display: 'block', marginBottom: 4 }}>Model</label>
              {fetchedModels.length > 0 ? (
                <select value={model} onChange={e => setModel(e.target.value)}
                  style={{ width: '100%', padding: '7px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--fg)', fontSize: 13 }}>
                  {fetchedModels.map(m => <option key={m} value={m}>{m}</option>)}
                </select>
              ) : (
                <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                  <input value={model} onChange={e => setModel(e.target.value)}
                    placeholder={provider === 'lmstudio' ? 'e.g. gemma-3-12b-it (from LM Studio)' : 'e.g. gpt-4o-mini'}
                    style={{ flex: 1, padding: '7px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--fg)', fontSize: 13, boxSizing: 'border-box' }} />
                  <Btn size="sm" onClick={fetchModels} disabled={fetchingModels}>
                    {fetchingModels ? 'Fetching…' : 'Fetch models'}
                  </Btn>
                </div>
              )}
              {fetchingModels && fetchedModels.length === 0 && (
                <div style={{ marginTop: 4, fontSize: 11, color: 'var(--fg-mute)' }}>Fetching available models…</div>
              )}
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <Btn size="sm" onClick={test} disabled={testing}>{testing ? 'Testing…' : 'Test connection'}</Btn>
              {testResult && (
                <span style={{ fontSize: 12, color: testResult.ok ? 'var(--st-offer)' : 'var(--st-rejected)' }}>
                  {testResult.ok ? '✓ Connected' : `✗ ${testResult.error || 'Failed'}`}
                </span>
              )}
            </div>
          </div>
        )}
      </div>

      <WizardNav step={2} onBack={onBack} onContinue={onNext} onSkip={onSkip} />
    </div>
  );
}

// Step 3: Location
function StepLocation({ preferredMetros, setPreferredMetros, locations, setLocations, filterEnabled, setFilterEnabled, allowRemote, setAllowRemote, allowHybrid, setAllowHybrid, allowOnsite, setAllowOnsite, onNext, onBack, onSkip }) {
  return (
    <div>
      <h2 style={{ margin: '0 0 8px', fontSize: 22, fontWeight: 700 }}>Where do you want to work?</h2>
      <p style={{ margin: '0 0 20px', color: 'var(--fg-mute)', lineHeight: 1.6 }}>
        Choose your target regions. Jobs outside your selection will be flagged as not matching your criteria. You can change this any time in Settings.
      </p>
      <LocationPicker
        preferredMetros={preferredMetros} setPreferredMetros={setPreferredMetros}
        preferredLocations={locations} setPreferredLocations={setLocations}
        filterEnabled={filterEnabled} setFilterEnabled={setFilterEnabled}
        allowRemote={allowRemote} setAllowRemote={setAllowRemote}
        allowHybrid={allowHybrid} setAllowHybrid={setAllowHybrid}
        allowOnsite={allowOnsite} setAllowOnsite={setAllowOnsite}
      />
      <WizardNav step={3} onBack={onBack} onContinue={onNext} onSkip={onSkip} />
    </div>
  );
}

// Step 4: Resume
function StepResume({ resumeText, setResumeText, onNext, onBack, onSkip }) {
  return (
    <div>
      <h2 style={{ margin: '0 0 8px', fontSize: 22, fontWeight: 700 }}>Add your resume</h2>
      <p style={{ margin: '0 0 16px', color: 'var(--fg-mute)', lineHeight: 1.6 }}>
        Jobhunt scores each job 0–100 for fit against your resume after extraction. Paste as plain text — no formatting needed.
      </p>
      <textarea
        value={resumeText}
        onChange={e => setResumeText(e.target.value)}
        placeholder="Paste your resume here as plain text…"
        rows={10}
        style={{ width: '100%', padding: '10px 12px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--fg)', fontSize: 13, lineHeight: 1.5, resize: 'vertical', boxSizing: 'border-box', fontFamily: 'var(--font-mono)' }}
      />
      <WizardNav step={4} onBack={onBack} onContinue={onNext} onSkip={onSkip} />
    </div>
  );
}

// Step 5: Summary
function StepSummary({ provider, apiKey, locations, preferredMetros, filterEnabled, resumeText, dontShow, setDontShow, onFinish, onBack, saving }) {
  const providerInfo = getOBProviders().find(p => p.id === provider);
  const rows = [
    { label: 'AI provider', value: providerInfo ? `${providerInfo.emoji} ${providerInfo.label}` : '—', set: !!providerInfo },
    ...( provider !== 'apple' ? [{ label: 'API key', value: apiKey ? '••••••••' : 'Not set', set: !!apiKey }] : [] ),
    { label: 'Location filter', value: !filterEnabled ? 'Open to relocation' : (preferredMetros ? `${preferredMetros.split(',').length} metro area(s)` : locations || 'Not set'), set: !filterEnabled || !!(preferredMetros || locations) },
    { label: 'Resume', value: resumeText ? `${resumeText.split(/\s+/).length.toLocaleString()} words` : 'Not set', set: !!resumeText },
  ];
  return (
    <div>
      <div style={{ fontSize: 40, marginBottom: 12, textAlign: 'center' }}>🎉</div>
      <h2 style={{ margin: '0 0 8px', fontSize: 22, fontWeight: 700, textAlign: 'center' }}>You're all set</h2>
      <p style={{ margin: '0 0 24px', color: 'var(--fg-mute)', textAlign: 'center', lineHeight: 1.6 }}>
        Here's what was configured. You can update anything in Settings at any time.
      </p>
      <div style={{ borderRadius: 8, border: '1px solid var(--border)', overflow: 'hidden', marginBottom: 24 }}>
        {rows.map((r, i) => (
          <div key={r.label} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '10px 14px', borderTop: i > 0 ? '1px solid var(--border)' : 'none', background: 'var(--bg-elev)' }}>
            <span style={{ fontSize: 13, color: 'var(--fg-mute)' }}>{r.label}</span>
            <span style={{ fontSize: 13, color: r.set ? 'var(--fg)' : 'var(--fg-faint)', fontFamily: r.set ? 'inherit' : undefined }}>
              {r.set ? '✓ ' : ''}{r.value}
            </span>
          </div>
        ))}
      </div>
      <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--fg-mute)', cursor: 'pointer', userSelect: 'none', marginBottom: 4 }}>
        <input type="checkbox" checked={dontShow} onChange={e => setDontShow(e.target.checked)} style={{ cursor: 'pointer' }} />
        Don't show this setup wizard again
      </label>
      <WizardNav step={5} onBack={onBack} onContinue={onFinish} continueLabel="Start using Jobhunt" saving={saving} />
    </div>
  );
}

function OnboardingWizard({ onClose }) {
  const s = window.JH_SETTINGS || {};
  const parseBool = v => String(v).toLowerCase() !== 'false' && v !== '0';

  const [step, setStep] = React.useState(0);
  const [provider, setProvider] = React.useState(s.llm_provider || 'lmstudio');
  const [apiKey, setApiKey] = React.useState('');
  const [baseUrl, setBaseUrl] = React.useState(s.llm_base_url || 'http://127.0.0.1:1234');
  const [model, setModel] = React.useState(s.llm_model || '');
  const [locations, setLocations] = React.useState(s.preferred_locations || '');
  const [preferredMetros, setPreferredMetros] = React.useState(s.preferred_metros || '');
  const [filterEnabled, setFilterEnabled] = React.useState(parseBool(s.location_filter_enabled ?? 'true'));
  const [allowRemote, setAllowRemote] = React.useState(parseBool(s.location_allow_remote ?? true));
  const [allowHybrid, setAllowHybrid] = React.useState(parseBool(s.location_allow_hybrid ?? true));
  const [allowOnsite, setAllowOnsite] = React.useState(parseBool(s.location_allow_onsite ?? true));
  const [resumeText, setResumeText] = React.useState(s.resume_text || '');
  const [dontShow, setDontShow] = React.useState(true);
  const [saving, setSaving] = React.useState(false);

  function next() { setStep(v => Math.min(v + 1, TOTAL_STEPS - 1)); }
  function back() { setStep(v => Math.max(v - 1, 0)); }
  function skipToSummary() { setStep(TOTAL_STEPS - 1); }

  async function finish() {
    setSaving(true);
    try {
      await fetch('/api/settings', {
        method: 'PATCH',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          llm_provider: provider,
          llm_api_key: apiKey,
          llm_base_url: baseUrl,
          llm_model: model,
          preferred_locations: locations,
          preferred_metros: preferredMetros,
          location_filter_enabled: String(filterEnabled),
          location_allow_remote: String(allowRemote),
          location_allow_hybrid: String(allowHybrid),
          location_allow_onsite: String(allowOnsite),
          resume_text: resumeText,
        }),
      });
      if (dontShow) localStorage.setItem(window.WELCOME_KEY || 'jh.welcome_dismissed', '1');
      localStorage.removeItem('jobhunt.force_first_run');
    } finally {
      setSaving(false);
      onClose();
    }
  }

  const overlayStyle = {
    position: 'fixed', inset: 0, zIndex: 1000,
    background: 'rgba(0,0,0,0.72)',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    padding: 20,
  };
  const cardStyle = {
    background: 'var(--bg-elev)',
    border: '1px solid var(--border-strong)',
    borderRadius: 14,
    width: '100%',
    maxWidth: 560,
    maxHeight: 'calc(100vh - 40px)',
    overflowY: 'auto',
    padding: '36px 44px 32px',
    position: 'relative',
  };

  const stepProps = { provider, setProvider, apiKey, setApiKey, baseUrl, setBaseUrl, model, setModel,
    locations, setLocations, preferredMetros, setPreferredMetros, filterEnabled, setFilterEnabled,
    allowRemote, setAllowRemote, allowHybrid, setAllowHybrid, allowOnsite, setAllowOnsite,
    resumeText, setResumeText, dontShow, setDontShow };

  return (
    <div style={overlayStyle}>
      <div className="jh-root" data-theme={document.querySelector('.jh-root')?.dataset.theme || 'auto'} style={{ width: '100%', maxWidth: 560 }}>
        <div style={cardStyle}>
          <StepDots step={step} />
          {step === 0 && <StepWelcome onNext={next} onDemo={async () => {
            const res = await fetch('/api/db/switch', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ mode: 'demo' }) });
            if (!res.ok) { alert(`Failed to switch to demo: ${(await res.json().catch(() => ({}))).error || res.status}`); return; }
            localStorage.setItem(window.WELCOME_KEY || 'jh.welcome_dismissed', '1');
            localStorage.removeItem('jobhunt.force_first_run');
            const curCols = localStorage.getItem('jobhunt.columns');
            if (curCols) localStorage.setItem('jobhunt.columns.pre-demo', curCols);
            else localStorage.removeItem('jobhunt.columns.pre-demo');
            localStorage.setItem('jobhunt.columns', JSON.stringify(["status", "company", "title", "fit", "location", "salaryMin", "salaryMax"]));
            const curSort = localStorage.getItem('jobhunt.sort');
            if (curSort) localStorage.setItem('jobhunt.sort.pre-demo', curSort);
            else localStorage.removeItem('jobhunt.sort.pre-demo');
            localStorage.setItem('jobhunt.sort', JSON.stringify({ key: "fitScore", dir: "desc" }));
            window.location.replace('#/dashboard');
            window.location.reload();
          }} />}
          {step === 1 && <StepExtension onNext={next} onBack={back} />}
          {step === 2 && <StepAI {...stepProps} onNext={next} onBack={back} onSkip={skipToSummary} />}
          {step === 3 && <StepLocation {...stepProps} onNext={next} onBack={back} onSkip={skipToSummary} />}
          {step === 4 && <StepResume {...stepProps} onNext={next} onBack={back} onSkip={skipToSummary} />}
          {step === 5 && <StepSummary {...stepProps} onFinish={finish} onBack={back} saving={saving} />}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { OnboardingWizard });
