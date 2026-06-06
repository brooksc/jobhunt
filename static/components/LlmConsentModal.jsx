// Jobhunt — LLM provider consent modal (App Store 5.1.2(i))
// Shown when the user selects a cloud AI provider for the first time.

const LLM_CONSENT_PROVIDER_LABELS = {
  anthropic: "Anthropic",
  google: "Google Gemini",
  openrouter: "OpenRouter",
  openai: "OpenAI",
};

const LLM_CONSENT_PRIVACY_URLS = {
  anthropic: "https://www.anthropic.com/privacy",
  google: "https://policies.google.com/privacy",
  openrouter: "https://openrouter.ai/privacy",
  openai: "https://openai.com/policies/privacy-policy",
};

// Props: provider (string), onAccept(), onDecline()
function LlmConsentModal({ provider, onAccept, onDecline }) {
  const label = LLM_CONSENT_PROVIDER_LABELS[provider] || provider;
  const privacyUrl = LLM_CONSENT_PRIVACY_URLS[provider];

  return (
    <AppDialog
      title={`Share data with ${label}?`}
      onClose={onDecline}
      maxWidth={460}
      actions={[
        { label: "Decline", kind: "ghost", onClick: onDecline },
        { label: "Accept", kind: "accent", onClick: onAccept },
      ]}
    >
      <div style={{ fontSize: 13, lineHeight: 1.55, color: "var(--fg)" }}>
        <p style={{ margin: "0 0 10px" }}>
          To use <strong>{label}</strong> for AI-powered extraction and job fit scoring,
          Jobhunt will send your <strong>job descriptions and resume text</strong> to{" "}
          {label}&rsquo;s servers.
        </p>
        <p style={{ margin: "0 0 10px" }}>
          Your data is processed according to {label}&rsquo;s privacy policy.
        </p>
        {privacyUrl && (
          <p style={{ margin: "0 0 4px" }}>
            <a
              href={privacyUrl}
              onClick={e => { e.preventDefault(); window.open(privacyUrl, "_blank", "noopener,noreferrer"); }}
              style={{ color: "var(--accent)", textDecoration: "underline", cursor: "pointer" }}
            >
              View {label} Privacy Policy
            </a>
          </p>
        )}
      </div>
    </AppDialog>
  );
}
