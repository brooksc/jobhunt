---
id: TASK-567
title: 'Settings: include cloud consent in AI readiness and queue gating'
status: Done
assignee: []
created_date: '2026-06-20 04:07'
updated_date: '2026-06-27 00:57'
labels:
  - audit
  - settings
  - llm
  - workflow
dependencies: []
modified_files:
  - core/LLM/AIReadiness.swift
  - core/LLM/QueueActor.swift
  - app/Views/Components/AIConfig.swift
  - app/Views/Components/SetupChecklistCard.swift
  - app/Shell/AppServices.swift
  - tests/CoreTests/AIReadinessTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `AIReadiness.isConfigured` only checks model/API key (`core/LLM/AIReadiness.swift`) while `QueueActor` enforces consent later inside each running request (`core/LLM/QueueActor.swift`). The setup checklist uses `AIConfig.isConfigured`, so a cloud provider with model/key but missing consent can appear fully configured even though queued extraction/fit work will fail with `ConsentError.notConsented` after the row has already been marked running.

Why it matters: This splits the domain concept of 'AI is usable' across separate checks. Users can see setup as complete, enqueue work, and then lose queue progress to avoidable request failures instead of getting the same setup nudge used for missing model/key. It also makes future provider changes fragile because callers must remember to check readiness and consent separately.

Suggested implementation: Introduce a single readiness result that represents 'can send job/resume data now', including provider, model, API key, base URL, and consent. Return a typed reason such as `missingModel`, `missingAPIKey`, or `missingConsent`. Use it in `AIConfig`, `SetupChecklistCard`, and `AppServices`/`QueueActor` provider gate so missing consent leaves work queued and deep-links to the AI settings consent flow rather than failing individual requests. Keep the immediate pre-provider consent guard as defense in depth for consent revoked after a request starts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cloud providers with model and API key but no consent are not reported as AI-configured in setup/status UI.
- [x] #2 The queue provider gate treats missing consent like a setup prerequisite and leaves queued work queued instead of marking requests failed before provider execution.
- [x] #3 The existing pre-provider consent guard remains in place to prevent data transmission if consent changes after the queue gate.
- [x] #4 Unit tests cover hosted provider with missing consent, hosted provider with consent, local provider without consent, and remote custom provider consent behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AIReadiness.isConfigured now includes cloud consent: the full form takes baseURL + a resolved `consented` flag and returns false when consent is missing; the SettingsStore convenience resolves consent via ConsentHelper.isConsented(provider:settings:). Because AIConfig and the QueueActor provider gate both use the convenience, a cloud provider with model+key but no consent now reads as not-configured in the UI (AC#1) and the queue gate leaves the work queued (emits .providerNotConfigured and breaks) instead of starting it and failing with ConsentError (AC#2). The pre-provider consent guard remains for consent revoked after the gate (AC#3, shared with TASK-536). Local providers resolve consented=true (auto-consent). Tests cover hosted missing-consent/with-consent, local, and custom remote-with-consent (AC#4). Full CoreTests (951) green; lint clean. Commit c7fea75.
<!-- SECTION:FINAL_SUMMARY:END -->
