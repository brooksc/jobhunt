---
id: TASK-056
title: >-
  Settings screen: provider config + test, location filter, resumes (PDFKit),
  debug, LLM consent gate
status: To Do
assignee: []
created_date: '2026-06-07 22:50'
labels:
  - swift-rewrite
  - ui
  - screen
milestone: m-1
dependencies:
  - TASK-045
  - TASK-035
  - TASK-042
  - TASK-044
documentation:
  - swift-plan.md
  - static/screens/settings.jsx
  - static/components/LlmConsentModal.jsx
priority: high
ordinal: 3300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the Settings screen (3 tabs) including the App Store-required cloud-LLM consent gate.

## Read first
- swift-plan.md §10.2 #9 (Settings tabs + fields), §13.3 (consent UI — Guideline 5.1.2(i), per-provider, localhost bypass), §8.7 (cost/pricing in Debug), §6.3 (SettingsStore/Keychain).
- Legacy static/screens/settings.jsx (1244 lines) and static/components/LlmConsentModal.jsx — the authority for provider setup (LM Studio/OpenAI/Anthropic/Google/OpenRouter/Custom/Apple Intelligence), per-provider config, model fetch + test connection, location filter + remote/hybrid/onsite toggles, resume CRUD + active, availability auto-check, debug (LLM debug log, cost pricing inputs, OpenRouter rotation).

## Implement (app/Views/Settings/)
- Tab 1 Settings: provider picker + per-provider config (base URL / API key→Keychain), model dropdown (fetched via task-042 provider model list) or manual entry, Test connection (runs provider capability check), location filter + toggles, site/followup intervals.
- Tab 2 Resumes: list/add/edit/delete/set-active; import text or PDF via PDFKit (extract text); backfill fit scores on add (via engine), recompute on delete.
- Tab 3 Debug: LLM debug log view, cost pricing input/output (CostEstimator), OpenRouter free-tier rotation toggle, availability auto-check settings.
- **Consent gate:** port LlmConsentModal — before saving/using a cloud provider, show per-provider data-disclosure + privacy link, persist llm_consent_<provider>; localhost (LM Studio, Apple) bypass. Block extraction until consent recorded (coordinate with QueueActor check).
- Switching FROM Apple offers bulk reset-extraction (task-046).

## Dependencies
Depends on task-045 (shell), task-035 (SettingsStore/Keychain/consent), task-042 (provider test/model fetch), task-044 (cost + backfill). 

## Tests (AppUITests + unit)
- Provider switch persists; Test connection success/failure surfaced; consent modal blocks cloud use until accepted and localhost bypasses; resume add/edit/delete/active; PDF text extraction.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 3 tabs (Settings/Resumes/Debug) reproduce settings.jsx fields and behavior
- [ ] #2 Provider config + model fetch + Test connection for all providers; API keys in Keychain
- [ ] #3 Location filter + remote/hybrid/onsite toggles + intervals persist
- [ ] #4 Resumes CRUD + active + PDF/text import (PDFKit); fit backfill on add, recompute on delete
- [ ] #5 Consent gate blocks cloud-provider use until per-provider consent accepted; localhost bypasses (§13.3)
- [ ] #6 Debug tab: LLM log, cost pricing inputs, OpenRouter rotation, availability auto-check
- [ ] #7 XCUITest covers provider switch, consent flow, resume CRUD
<!-- AC:END -->
