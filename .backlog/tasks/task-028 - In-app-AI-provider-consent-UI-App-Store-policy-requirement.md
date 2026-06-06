---
id: TASK-028
title: In-app AI provider consent UI (App Store policy requirement)
status: To Do
assignee: []
created_date: '2026-06-06 22:40'
labels:
  - ui
  - privacy
  - mas
milestone: m-0
dependencies: []
priority: medium
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem

Apple App Store guideline 5.1.2(i) requires that apps which share user data with third-party AI providers must:

1. **Explicitly disclose** which provider will receive the data and what data (job description text, resume)
2. **Obtain per-provider consent** before the first API call to that provider
3. **Not bundle** this consent with a general "by using the app you agree" acceptance

The app currently sends job description text and resume content to whichever cloud LLM provider the user configures (Anthropic, OpenAI/OpenRouter, Google Gemini) without any in-app disclosure or consent flow. This is a blocking issue for App Store submission.

Local providers (LM Studio, Ollama — anything calling `http://localhost` or `http://127.0.0.1`) do NOT require this consent, as data stays on-device.

## What data is sent

When a cloud provider is active:
- Job description text (from the captured page)
- Resume text (from the user's configured resume)
- These are sent for extraction (structured data parsing) and fit scoring

## Implementation

### Settings DB change

Add a `llm_consent` column (or JSON field) to the settings table to persist consent per provider:

In `server/db.js`, add to `SETTINGS_DEFAULTS`:
```js
llm_consent_anthropic: '0',
llm_consent_google: '0',
llm_consent_openrouter: '0',
llm_consent_openai: '0',
```

### Consent check in extract.js

Before any outbound LLM call to a cloud provider, check the corresponding consent setting. If consent has not been given, emit an IPC event to the renderer to show the consent modal. Block the extraction until consent is given or denied.

The simplest implementation: have `extract.js` throw a specific error (e.g., `{ code: 'CONSENT_REQUIRED', provider: 'anthropic' }`) which bubbles up to the API response. The UI catches this response and shows the modal, then re-queues the job after consent is recorded.

### Consent modal (React component)

Location: `static/screens/` — add a modal component or extend the existing settings UI.

The modal must include:
- **What data**: "Your job descriptions and resume text will be sent to [Provider Name]"
- **Why**: "for AI-powered extraction and job fit scoring"
- **Provider's privacy policy link** (open in external browser via `shell.openExternal`)
- **Accept** button — saves `llm_consent_<provider> = '1'` to settings
- **Cancel / Use local model** button — saves `'0'`, redirects user to Settings to pick a local provider

Show the modal when:
1. User first activates a cloud provider in Settings (proactive)
2. An extraction/fit-score API call encounters `CONSENT_REQUIRED` for the active provider (reactive fallback)

Do NOT show the modal for providers the user has already consented to.

### Consent links

| Provider | Privacy policy URL |
|----------|-------------------|
| Anthropic | https://www.anthropic.com/privacy |
| Google | https://policies.google.com/privacy |
| OpenRouter | https://openrouter.ai/privacy |
| OpenAI (compatible) | https://openai.com/policies/privacy-policy |

## Scope boundary

This task covers the consent flow only — not a full privacy settings screen overhaul. The goal is a minimal, correct implementation that satisfies the App Store guideline. The consent modal can be a simple dialog overlay using existing UI patterns in the codebase.

## Verification

- Configuring a cloud provider for the first time shows the consent modal before any API call is made
- Clicking Accept persists the consent and allows extractions to proceed without showing the modal again
- Clicking Cancel/Use local model does not persist consent and no extraction is attempted
- Switching to a different cloud provider requires separate consent for that provider
- Local providers (localhost/127.0.0.1) bypass the consent check entirely
- Consent state survives app restart (persisted in settings DB)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Per-provider consent flags are stored in the settings table (llm_consent_anthropic, llm_consent_google, etc.)
- [ ] #2 No cloud LLM API call is made before the corresponding consent flag is '1'
- [ ] #3 Consent modal clearly states which data is sent, to which provider, and why
- [ ] #4 Modal includes a link to the provider's privacy policy that opens in an external browser
- [ ] #5 Accept saves consent and resumes extraction without showing modal again for that provider
- [ ] #6 Cancel/decline does not save consent and does not trigger an LLM call
- [ ] #7 Local providers (localhost, 127.0.0.1) skip the consent check entirely
- [ ] #8 Consent persists across app restarts
<!-- AC:END -->
