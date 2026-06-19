---
id: TASK-537
title: 'LLM: persist provider endpoint provenance on request attempts'
status: To Do
assignee: []
created_date: '2026-06-19 04:57'
labels:
  - audit
  - llm
  - provider
  - diagnostics
  - privacy
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Models/LLMRequestAttempt.swift
  - core/LLM/LLMProviderFactory.swift
  - core/Settings/ConsentHelper.swift
  - app/Views/Settings/DebugTab.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `LLMRequestAttempt` has a `baseURL` field, and `QueueActor` has the provider/base URL settings at the point it enforces consent, but attempt rows are created without `baseURL`. This leaves attempts without endpoint provenance even though the endpoint is central to distinguishing local LM Studio/custom calls from remote custom/cloud calls.

Why this matters: the app's privacy model depends on whether data was sent to a local loopback endpoint or a remote provider. When a request fails, gets retried, or is later audited, the attempt record should show which endpoint policy was in force. Without it, diagnostics must infer from current settings, which may have changed since the attempt ran.

Suggested implementation: populate `LLMRequestAttempt.baseURL` from the effective provider endpoint at attempt time, using the same provider/base URL resolution rules as provider creation and consent decisions. For hosted providers, record the canonical API base URL; for custom/LM Studio, record the normalized configured URL. Avoid storing API keys or request paths that could include credentials. Consider displaying the endpoint in debug/attempt detail views only where appropriate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Successful extraction and fit attempts persist the effective provider base URL used for the attempt.
- [ ] #2 Failed provider attempts persist the same effective base URL when settings are available.
- [ ] #3 Consent-blocked/pre-provider attempts persist the endpoint that caused the consent decision where safe.
- [ ] #4 Hosted providers use canonical base URLs; custom and LM Studio use normalized configured base URLs without credentials.
- [ ] #5 Tests cover local loopback, remote custom, and hosted-provider attempt provenance.
- [ ] #6 No API keys, auth headers, or credential-bearing query parameters are persisted.
<!-- AC:END -->
