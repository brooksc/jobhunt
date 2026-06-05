// Jobhunt — Help documentation

const HELP_SECTIONS = [
  {
    title: "Start here",
    body: [
      "Jobhunt is a local-first job tracker. The Chrome extension captures job pages, the local service stores them in SQLite, and the app helps you extract structured fields, track follow-ups, review data quality, and export your pipeline.",
      "A normal workflow is: capture jobs from the browser, run AI extraction, review Data Quality, move promising jobs through statuses, and use Needs Action for follow-ups.",
    ],
  },
  {
    title: "Initial setup",
    items: [
      "Launch the Jobhunt app. The local service starts automatically and the UI opens in your browser.",
      "Install the Chrome extension — see the Capture tab for instructions. Keep the app running while capturing pages.",
      "Open Settings to configure your AI provider, preferred locations, work arrangements, follow-up defaults, and resume text for fit scoring.",
      "Use Test connection in Settings before queuing a large extraction batch.",
    ],
  },
  {
    title: "Capturing jobs",
    items: [
      "Open a job posting in Chrome or Chromium and click the Jobhunt extension button.",
      "If the service is unavailable, the extension queues the capture and retries later.",
      "Captured jobs appear in Jobs. The sidebar Extension status shows whether captures have happened recently.",
      "If a posting is poorly captured, open the job detail panel and inspect Capture diagnostics, selected text, structured data, and raw source fields.",
    ],
  },
  {
    title: "Jobs",
    items: [
      "Use the Jobs table to search, filter, sort, select rows, bulk-change status, queue AI work, compare selected jobs, and export CSV.",
      "Open a row to view details, edit extracted fields, inspect timeline events, read captured descriptions, view raw diagnostics, re-run AI, or mark a job unavailable.",
      "Saved views in the sidebar store a named combination of filters and search — create one from the current filter state using the bookmark icon. Common uses: active applications, remote-only, recent captures.",
      "Press ⌘K (Mac) or Ctrl-K (Windows/Linux) from anywhere in the app to jump to Jobs search.",
    ],
  },
  {
    title: "AI extraction",
    items: [
      "Run AI extraction from Dashboard, Jobs, or the LLM Queue after your provider and model are configured.",
      "Use Full extraction when the page needs complete parsing, Missing fields only for cleanup, and Fit score only after adding or changing your resume.",
      "The LLM Queue shows outstanding, running, failed, and completed requests with attempt history and retry controls.",
      "Failed attempts are durable. Enable LLM debug logging in Settings → Debug if extraction fails silently.",
    ],
  },
  {
    title: "Fit scoring",
    items: [
      "Fit scoring rates each job 0–100 against your resume and breaks the score down by dimension (skills match, seniority, location, etc.).",
      "Add your resume in Settings → Resume as plain text. Re-run Fit score only mode after updating it to refresh all scores without re-extracting.",
      "The fit score appears as a badge in the Jobs table and as a full dimension breakdown in the job detail panel.",
      "Jobs with no resume configured show no fit score — the badge is absent rather than zero.",
    ],
  },
  {
    title: "Data Quality",
    items: [
      "Data Quality groups active jobs with missing or suspect fields, stale captures, short captures, failed extraction, and AI-only gaps.",
      "Use Browser recapture checklist for problems that likely need a better capture. Use AI re-run checklist for records that can probably be fixed by extraction.",
      "Open visible jobs to review them one at a time, select them in Jobs for bulk work, or dismiss visible rows after you have reviewed the gap.",
      "Reviewed jobs remain available under the Reviewed filter so you can undo a dismissal.",
    ],
  },
  {
    title: "Needs Action",
    items: [
      "Needs Action collects follow-ups due today or overdue.",
      "Follow-up dates are created from job detail actions and use the default interval configured in Settings.",
      "Complete actions from the list when you have sent an email, applied, checked a status page, or intentionally deferred the job.",
    ],
  },
  {
    title: "Sites",
    items: [
      "Use Sites to track company or job-board pages that should be reviewed periodically even when no specific posting is captured.",
      "Add a site URL from the Sites page. New sites inherit the review interval from Settings.",
      "Reviewing a site updates its last-reviewed and next-review dates so recurring prospecting does not disappear from the workflow.",
    ],
  },
  {
    title: "Duplicates",
    items: [
      "Duplicates groups captures that look like the same job posting.",
      "Compare a group to decide which record to keep, merge, archive, or ignore.",
      "Use duplicate review after large capture sessions or after retry queues flush several saved postings at once.",
    ],
  },
  {
    title: "Settings and data",
    items: [
      "Settings controls the local service status, extension status, availability automation, LLM provider, resume text, location filtering, defaults, export, and local paths.",
      "The app stores runtime data under the config directory shown in Settings unless JOBHUNT_CONFIG_DIR or JOBHUNT_DB_PATH is set.",
      "Export CSV from Settings or Jobs when you need a spreadsheet copy of the current job table.",
    ],
  },
];

const TROUBLESHOOTING_SECTION = {
  title: "Troubleshooting",
  items: [
    "No new captures: confirm the local service is running, reload the extension, and check the sidebar Extension status.",
    "Extraction does not run: check Settings provider details, load or select a model, run Test connection, then inspect LLM Queue failures.",
    "Fields look wrong: inspect Capture diagnostics, re-run AI, or recapture the page with more visible job text selected.",
    "Availability checks mark jobs unavailable: open the source URL from job details and restore the status manually if the site blocks automated checks.",
    "UI looks stale: use Reload in the top bar or restart the local service.",
  ],
};

function AiProviderCard({ badge, badgeKind = "local", name, children }) {
  return (
    <div className="jh-help-ai__card">
      <div className="jh-help-ai__card-head">
        <strong>{name}</strong>
        <span className={`jh-help-ai__badge jh-help-ai__badge--${badgeKind}`}>{badge}</span>
      </div>
      {children}
    </div>
  );
}

function AiSetupContent() {
  return (
    <div className="jh-help-ai">
      <p className="jh-help-ai__intro">
        AI extraction reads captured job descriptions and writes back structured fields — title, company, location, salary, skills, seniority, and a fit score against your resume. You need one provider configured in <strong>Settings → LLM provider</strong> before extraction will run.
      </p>

      <div className="jh-help-ai__grid">

        {/* ── LM Studio ── */}
        <AiProviderCard name="LM Studio" badge="Local · free" badgeKind="local">
          <p>Runs entirely on your machine. No API key, no data leaves your computer. Best choice if you have a modern Mac with Apple Silicon — models run fast on the GPU via Metal.</p>
          <ol>
            <li>Download and install from <a href="https://lmstudio.ai" target="_blank" rel="noopener noreferrer">lmstudio.ai</a> (Mac, Windows, Linux).</li>
            <li>Open LM Studio, go to <strong>Discover</strong>, and search for a model. Good starting points: <code>gemma-3-12b-it</code>, <code>qwen2.5-7b-instruct</code>, or <code>llama-3.2-3b-instruct</code> for lower RAM.</li>
            <li>Download the model, then open the <strong>Developer</strong> tab and click <strong>Start Server</strong>. The server runs on <code>http://127.0.0.1:1234</code> by default.</li>
            <li>In Jobhunt Settings: choose <strong>LM Studio</strong> as provider, leave the base URL as-is, select your loaded model, and click <strong>Test connection</strong>.</li>
          </ol>
          <p className="jh-help-ai__note">Requires ~8 GB RAM for a 7B model, ~16 GB for a 12B model. Quality improves significantly with larger models.</p>
        </AiProviderCard>

        {/* ── Ollama ── */}
        <AiProviderCard name="Ollama" badge="Local · free" badgeKind="local">
          <p>Command-line model runner with a large model library. No API key needed. Exposes an OpenAI-compatible endpoint at <code>localhost:11434</code>.</p>
          <ol>
            <li>Install from <a href="https://ollama.com" target="_blank" rel="noopener noreferrer">ollama.com</a> (Mac, Windows, Linux) or via Homebrew: <code>brew install ollama</code>.</li>
            <li>Pull a model in Terminal: <code>ollama pull gemma3:12b</code> or <code>ollama pull llama3.2:3b</code> for lower RAM.</li>
            <li>Start the server: <code>ollama serve</code> (runs automatically after install on Mac).</li>
            <li>In Jobhunt Settings: choose <strong>Custom (OpenAI-compatible)</strong> as provider, set base URL to <code>http://localhost:11434/v1</code>, leave API key blank, and type your model name (e.g. <code>gemma3:12b</code>).</li>
          </ol>
          <p className="jh-help-ai__note">Run <code>ollama list</code> to see downloaded models. Use <code>ollama ps</code> to check if a model is loaded.</p>
        </AiProviderCard>

        {/* ── OpenAI ── */}
        <AiProviderCard name="OpenAI" badge="Cloud · paid" badgeKind="cloud">
          <p>High-quality models with no local setup. Charges per token — extraction of a typical job posting costs a fraction of a cent.</p>
          <ol>
            <li>Create an account at <a href="https://platform.openai.com" target="_blank" rel="noopener noreferrer">platform.openai.com</a> and add a payment method under Billing.</li>
            <li>Go to <a href="https://platform.openai.com/api-keys" target="_blank" rel="noopener noreferrer">platform.openai.com/api-keys</a> and create a new secret key.</li>
            <li>In Jobhunt Settings: choose <strong>OpenAI</strong> as provider, paste your key (starts with <code>sk-…</code>), and pick a model.</li>
          </ol>
          <p className="jh-help-ai__note"><strong>Recommended models:</strong> <code>gpt-4o-mini</code> for best value, <code>gpt-4o</code> for highest accuracy. <code>o3-mini</code> is strong for fit scoring but slower.</p>
        </AiProviderCard>

        {/* ── Anthropic ── */}
        <AiProviderCard name="Anthropic" badge="Cloud · paid" badgeKind="cloud">
          <p>Claude models are strong at structured extraction and following detailed instructions. Competitive pricing at higher quality tiers.</p>
          <ol>
            <li>Create an account at <a href="https://console.anthropic.com" target="_blank" rel="noopener noreferrer">console.anthropic.com</a> and add a payment method.</li>
            <li>Go to <a href="https://console.anthropic.com/account/keys" target="_blank" rel="noopener noreferrer">console.anthropic.com/account/keys</a> and create an API key.</li>
            <li>In Jobhunt Settings: choose <strong>Anthropic</strong> as provider, paste your key (starts with <code>sk-ant-…</code>), and pick a model.</li>
          </ol>
          <p className="jh-help-ai__note"><strong>Recommended models:</strong> <code>claude-haiku-4-5</code> for fast/cheap extraction, <code>claude-sonnet-4-6</code> for best quality.</p>
        </AiProviderCard>

        {/* ── Google Gemini ── */}
        <AiProviderCard name="Google Gemini" badge="Cloud · free tier" badgeKind="cloud">
          <p>Gemini models are available via Google AI Studio with a generous free tier — enough to extract hundreds of job postings per day at no cost.</p>
          <ol>
            <li>Go to <a href="https://aistudio.google.com" target="_blank" rel="noopener noreferrer">aistudio.google.com</a> and sign in with a Google account.</li>
            <li>Click <strong>Get API key</strong> → <strong>Create API key</strong>. No billing setup required for the free tier.</li>
            <li>In Jobhunt Settings: choose <strong>Google Gemini</strong> as provider, paste your key, and pick a model.</li>
          </ol>
          <p className="jh-help-ai__note"><strong>Recommended models:</strong> <code>gemini-2.5-flash</code> for speed and value, <code>gemini-2.5-pro</code> for maximum quality. Free tier rate limits may slow large batches.</p>
        </AiProviderCard>

        {/* ── OpenRouter ── */}
        <AiProviderCard name="OpenRouter" badge="Cloud · pay-per-use" badgeKind="cloud">
          <p>A proxy that gives you access to dozens of models — OpenAI, Anthropic, Google, Meta, Mistral — with a single API key. Useful for comparing models or accessing ones not directly available in your region.</p>
          <ol>
            <li>Create an account at <a href="https://openrouter.ai" target="_blank" rel="noopener noreferrer">openrouter.ai</a> and add credits under Billing.</li>
            <li>Go to <a href="https://openrouter.ai/keys" target="_blank" rel="noopener noreferrer">openrouter.ai/keys</a> and create a key.</li>
            <li>In Jobhunt Settings: choose <strong>OpenRouter</strong> as provider, paste your key, and pick from the model list or type any OpenRouter model ID.</li>
          </ol>
          <p className="jh-help-ai__note"><strong>Good starting models:</strong> <code>google/gemini-2.5-flash</code> (fast), <code>anthropic/claude-sonnet-4-6</code> (quality), <code>meta-llama/llama-3.3-70b-instruct</code> (open-weight quality).</p>
        </AiProviderCard>

      </div>

      <div className="jh-help-ai__tips">
        <h3>Tips</h3>
        <ul>
          <li>Always click <strong>Test connection</strong> in Settings before running a batch — it confirms the provider is reachable and shows available models.</li>
          <li>Add your resume text in <strong>Settings → Resume</strong> to enable fit scoring. Fit scores appear as a 0–100 rating and a per-dimension breakdown in the job detail panel.</li>
          <li>Use <strong>Missing fields only</strong> mode after switching models to fill gaps without re-extracting everything.</li>
          <li>The <strong>LLM Queue</strong> page shows live progress, failed attempts with error details, and lets you pause, retry, or cancel individual requests.</li>
          <li>Enable <strong>LLM debug logging</strong> in Settings if extraction fails silently — it writes full request/response bodies to the log file shown in Settings.</li>
        </ul>
      </div>
    </div>
  );
}

function HelpPage() {
  const [helpPage, setHelpPage] = React.useState('setup');

  const tabs = [
    { id: 'setup', label: 'Setup' },
    { id: 'capture', label: 'Capture' },
    { id: 'extract', label: 'Extract' },
    { id: 'review', label: 'Review' },
    { id: 'followup', label: 'Follow Up' },
    { id: 'about', label: 'About', right: true },
  ];

  const workflowSteps = [
    { id: 'capture', Icon: Icon.Briefcase, label: 'Capture' },
    { id: 'extract', Icon: Icon.Sparkles, label: 'Extract' },
    { id: 'review', Icon: Icon.AlertTriangle, label: 'Review' },
    { id: 'followup', Icon: Icon.Bell, label: 'Follow Up' },
  ];

  const step = { fontSize: 13, padding: '7px 0', borderBottom: '1px solid var(--border)', display: 'flex', gap: 10, alignItems: 'flex-start' };
  const num = { flexShrink: 0, width: 20, height: 20, borderRadius: 10, background: 'var(--accent)', color: '#fff', fontSize: 11, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 1 };
  const code = { fontFamily: 'var(--font-mono)', fontSize: 12, background: 'var(--bg-elev-2)', border: '1px solid var(--border)', borderRadius: 4, padding: '1px 5px' };

  function HelpSection({ section }) {
    return (
      <section className="jh-help__section">
        <h2>{section.title}</h2>
        {section.body?.map((text) => <p key={text}>{text}</p>)}
        {section.items && <ul>{section.items.map((item) => <li key={item}>{item}</li>)}</ul>}
      </section>
    );
  }

  const S = Object.fromEntries(HELP_SECTIONS.map(s => [s.title, s]));

  return (
    <div className="jh-help">
      <div className="jh-help__intro">
        <div>
          <h1>Help</h1>
          <p>Operational guide for running the local job-search workflow end to end.</p>
        </div>
        <div className="jh-help__quick">
          {workflowSteps.map((ws, i) => (
            <React.Fragment key={ws.id}>
              {i > 0 && <span style={{ color: 'var(--fg-faint)', fontSize: 14, padding: '0 2px', border: 'none', background: 'none' }}>→</span>}
              <button
                onClick={() => setHelpPage(ws.id)}
                style={{
                  display: 'inline-flex', alignItems: 'center', gap: 6,
                  height: 26, padding: '0 8px',
                  border: `1px solid ${helpPage === ws.id ? 'var(--accent-border)' : 'var(--border)'}`,
                  borderRadius: 'var(--r-2)',
                  background: helpPage === ws.id ? 'var(--accent-bg)' : 'var(--bg-elev)',
                  color: helpPage === ws.id ? 'var(--accent)' : 'var(--fg)',
                  fontSize: 12, cursor: 'pointer', fontFamily: 'inherit',
                }}
              >
                <ws.Icon size={12} />{ws.label}
              </button>
            </React.Fragment>
          ))}
        </div>
      </div>

      {/* Tab bar */}
      <div style={{ display: 'flex', gap: 0, borderBottom: '1px solid var(--border)', marginBottom: 24, background: 'var(--bg)', alignItems: 'center' }}>
        {tabs.filter(t => !t.right).map(tab => {
          const active = helpPage === tab.id;
          return (
            <button key={tab.id} onClick={() => setHelpPage(tab.id)} style={{
              background: 'none', border: 'none', borderBottom: active ? '2px solid var(--accent)' : '2px solid transparent',
              color: active ? 'var(--fg)' : 'var(--fg-mute)', cursor: 'pointer',
              fontSize: 13, fontWeight: active ? 600 : 400, padding: '10px 16px 8px', marginBottom: -1,
            }}>{tab.label}</button>
          );
        })}
        <div style={{ flex: 1 }} />
        {tabs.filter(t => t.right).map(tab => {
          const active = helpPage === tab.id;
          return (
            <button key={tab.id} onClick={() => setHelpPage(tab.id)} style={{
              background: 'none', border: 'none', borderBottom: active ? '2px solid var(--accent)' : '2px solid transparent',
              color: active ? 'var(--fg)' : 'var(--fg-mute)', cursor: 'pointer',
              fontSize: 13, fontWeight: active ? 600 : 400, padding: '10px 16px 8px', marginBottom: -1,
            }}>{tab.label}</button>
          );
        })}
      </div>

      {/* Setup tab */}
      {helpPage === 'setup' && (
        <div className="jh-help__grid">
          <HelpSection section={S['Start here']} />
          <HelpSection section={S['Initial setup']} />
          <HelpSection section={S['Capturing jobs']} />
          <HelpSection section={S['AI extraction']} />
          <HelpSection section={S['Settings and data']} />
          <HelpSection section={TROUBLESHOOTING_SECTION} />
        </div>
      )}

      {/* Capture tab */}
      {helpPage === 'capture' && (
        <div>
          <section className="jh-help__section--wide" style={{ marginBottom: 28 }}>
            <h2>Chrome extension</h2>
            <div style={{ padding: '16px 18px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-elev)', maxWidth: 600 }}>
              <div style={{ fontWeight: 600, fontSize: 14, marginBottom: 14 }}>Install from the Chrome Web Store</div>
              <div style={step}><div style={num}>1</div><div>Visit <a href="https://chromewebstore.google.com/detail/jobhunt-capture/jekcbebhfeidkpapienoflbcaeeknlch" target="_blank" rel="noopener noreferrer">Jobhunt Capture on the Chrome Web Store</a> and click <strong>Add to Chrome</strong>.</div></div>
              <div style={step}><div style={num}>2</div><div>Click the puzzle-piece icon in Chrome's toolbar and pin <strong>Jobhunt Capture</strong> for quick access.</div></div>
              <div style={{ ...step, borderBottom: 'none', paddingBottom: 0 }}><div style={num}>3</div><div>Keep the Jobhunt service running (<span style={code}>npm start</span>), then open any job posting and click the icon.</div></div>
            </div>
          </section>
          <div className="jh-help__grid">
            <HelpSection section={S['Capturing jobs']} />
            <HelpSection section={S['Sites']} />
            <section className="jh-help__section">
              <h2>Add Job URL</h2>
              <p>Don't have the extension installed yet? Use <strong>Add Job URL</strong> in the Jobs toolbar. Paste any public job posting URL and Jobhunt fetches and captures the page server-side. Works for most public job boards — the extension gives better results on pages that require JavaScript rendering.</p>
            </section>
          </div>
        </div>
      )}

      {/* Extract tab */}
      {helpPage === 'extract' && (
        <div>
          <div className="jh-help__grid" style={{ marginBottom: 28 }}>
            <HelpSection section={S['AI extraction']} />
            <HelpSection section={S['Fit scoring']} />
          </div>
          <section className="jh-help__section--wide">
            <h2>AI provider setup</h2>
            <AiSetupContent />
          </section>
        </div>
      )}

      {/* Review tab */}
      {helpPage === 'review' && (
        <div className="jh-help__grid">
          <HelpSection section={S['Jobs']} />
          <HelpSection section={S['Data Quality']} />
          <HelpSection section={S['Duplicates']} />
          <section className="jh-help__section">
            <h2>Keyboard shortcuts</h2>
            <div style={{ display: 'grid', gridTemplateColumns: 'auto 1fr', gap: '6px 16px', alignItems: 'center', fontSize: 13 }}>
              {[
                ['⌘K / Ctrl-K', 'Focus Jobs search from anywhere'],
                ['↑ / ↓', 'Navigate between jobs in the table'],
                ['Enter', 'Open focused job detail'],
                ['Escape', 'Close detail panel / clear search'],
              ].map(([key, desc]) => (
                <React.Fragment key={key}>
                  <Kbd>{key}</Kbd>
                  <span style={{ color: 'var(--fg-mute)' }}>{desc}</span>
                </React.Fragment>
              ))}
            </div>
          </section>
        </div>
      )}

      {/* Follow Up tab */}
      {helpPage === 'followup' && (
        <div>
          <div className="jh-help__grid" style={{ marginBottom: 28 }}>
            {/* Pipeline */}
            <section className="jh-help__section jh-help__section--wide">
              <h2>Job pipeline</h2>
              <p>Move jobs through these statuses as your application progresses. Only <strong>Saved</strong>, <strong>Applied</strong>, <strong>Interview</strong>, and <strong>Offer</strong> are considered active and appear in default filters.</p>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 10, margin: '16px 0' }}>
                {[
                  { status: 'saved', color: 'var(--st-saved, var(--fg-mute))', label: 'Saved', desc: 'Captured and under consideration. Default state for all new jobs.' },
                  { status: 'applied', color: 'var(--st-applied, #4a90d9)', label: 'Applied', desc: 'Application submitted. Set a follow-up reminder to check status.' },
                  { status: 'interview', color: 'var(--st-interview, #9b6fd4)', label: 'Interview', desc: 'Actively interviewing. Track rounds and contacts in job notes.' },
                  { status: 'offer', color: 'var(--st-offer, #4caf6e)', label: 'Offer', desc: 'Offer received. Compare compensation against your criteria.' },
                ].map(({ status, color, label, desc }) => (
                  <div key={status} style={{ padding: '12px 14px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-elev)' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 5 }}>
                      <span style={{ width: 8, height: 8, borderRadius: 4, background: color, flexShrink: 0 }} />
                      <strong style={{ fontSize: 13 }}>{label}</strong>
                    </div>
                    <p style={{ margin: 0, fontSize: 12, color: 'var(--fg-mute)', lineHeight: 1.45 }}>{desc}</p>
                  </div>
                ))}
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 10 }}>
                {[
                  { status: 'rejected', color: 'var(--st-rejected, #e05c5c)', label: 'Rejected', desc: 'Application declined. Kept for reference — useful for identifying patterns.' },
                  { status: 'archived', color: 'var(--fg-faint)', label: 'Archived', desc: 'No longer pursuing. Removed from active views but preserved in history.' },
                  { status: 'not_available', color: 'var(--fg-faint)', label: 'Not available', desc: 'Posting is no longer live. Set automatically by availability checks or manually.' },
                ].map(({ status, color, label, desc }) => (
                  <div key={status} style={{ padding: '12px 14px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-elev)' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 5 }}>
                      <span style={{ width: 8, height: 8, borderRadius: 4, background: color, flexShrink: 0 }} />
                      <strong style={{ fontSize: 13 }}>{label}</strong>
                    </div>
                    <p style={{ margin: 0, fontSize: 12, color: 'var(--fg-mute)', lineHeight: 1.45 }}>{desc}</p>
                  </div>
                ))}
              </div>
            </section>
          </div>
          <div className="jh-help__grid">
            <HelpSection section={S['Needs Action']} />
            <section className="jh-help__section">
              <h2>Workflow tips</h2>
              <ul>
                <li>Change status from the job detail panel or select multiple rows in the Jobs table and use bulk status change.</li>
                <li>When you move a job to <strong>Applied</strong>, set a follow-up date immediately — it takes seconds and prevents applications from going silent.</li>
                <li>Use job notes to track recruiter names, interview rounds, and compensation details. Notes appear in the timeline.</li>
                <li>Filter Jobs by status using the sidebar or the status filter to see only active applications, or only offers.</li>
                <li>Rejected and archived jobs are hidden from default views but searchable — use the status filter to review past applications.</li>
              </ul>
            </section>
          </div>
        </div>
      )}
      {/* About tab */}
      {helpPage === 'about' && (
        <div style={{ maxWidth: 560 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 28 }}>
            <img src="/static/apple-touch-icon.png" alt="Jobhunt" style={{ width: 56, height: 56, borderRadius: 14, flexShrink: 0 }} />
            <div>
              <h2 style={{ margin: '0 0 2px', fontSize: 20 }}>Jobhunt</h2>
              <div style={{ fontSize: 13, color: 'var(--fg-mute)' }}>Version {(window.JH_SETTINGS || {}).version || '—'} · Local-first job tracker</div>
            </div>
          </div>

          <p style={{ fontSize: 14, lineHeight: 1.65, color: 'var(--fg-mute)', marginBottom: 24 }}>
            Jobhunt helps you manage a job search without spreadsheets or SaaS subscriptions. It captures job postings from the web, uses AI to extract structured data, scores opportunities against your resume, and keeps your pipeline organized locally on your machine.
          </p>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 28 }}>
            <a href="https://jobhunt-app.com" target="_blank" rel="noopener noreferrer"
              style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '10px 16px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-elev)', color: 'var(--fg)', textDecoration: 'none', fontSize: 13, width: 'fit-content' }}>
              <Icon.External size={14} />
              jobhunt-app.com
            </a>
            <a href="https://github.com/brooksc/jobhunt" target="_blank" rel="noopener noreferrer"
              style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '10px 16px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-elev)', color: 'var(--fg)', textDecoration: 'none', fontSize: 13, width: 'fit-content' }}>
              <Icon.External size={14} />
              github.com/brooksc/jobhunt
            </a>
          </div>

          <section className="jh-help__section">
            <h2>Privacy</h2>
            <ul>
              <li>All data is stored locally in a SQLite database on your machine. Nothing is sent to any remote server.</li>
              <li>When using a cloud AI provider (OpenAI, Anthropic, Google, OpenRouter), job posting text is sent to that provider's API for extraction. No other data is shared.</li>
              <li>When using LM Studio or Ollama, all AI processing stays on-device. No job data ever leaves your machine.</li>
              <li>The Chrome extension only communicates with the local Jobhunt service running on your machine (localhost).</li>
            </ul>
          </section>

          <section className="jh-help__section">
            <h2>Tech stack</h2>
            <ul>
              <li><strong>Server</strong>: Node.js with Express, SQLite via node:sqlite (built-in)</li>
              <li><strong>Frontend</strong>: React served as JSX — no build step</li>
              <li><strong>Desktop</strong>: Electron wraps the local service and browser UI</li>
              <li><strong>AI</strong>: Any OpenAI-compatible API endpoint (local or cloud)</li>
            </ul>
          </section>
        </div>
      )}
    </div>
  );
}

Object.assign(window, { HelpPage });
