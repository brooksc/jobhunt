---
id: TASK-512
title: >-
  Workflow: Treat missing LLM model as not configured instead of failing the
  queue
status: Done
assignee: []
created_date: '2026-06-19 01:31'
updated_date: '2026-06-19 02:29'
labels:
  - workflow
  - llm
  - onboarding
dependencies: []
references:
  - docs/workflow.md
  - app/Shell/AppServices.swift
  - app/Views/Components/AIConfigBanner.swift
  - core/LLM/QueueActor.swift
  - core/LLM/ExtractionEngine.swift
  - core/Settings/SettingsStore.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: The UI uses `AIConfig.isConfigured` to require both a selected model and, for hosted providers, an API key. The queue's `isProviderConfigured` closure in `AppServices` only checks API-key requirements. On a default install, `SettingsStore.llmModel` is empty, but the queue proceeds, `ExtractionEngine.extract` throws `noModelSelected`, and the request can fail/auto-pause instead of producing the setup-nudge workflow described in `docs/workflow.md`.

Why this matters: New users or users who switch providers without selecting a model can see queued jobs fail or the AI queue auto-pause, even though the correct action is simply to finish AI setup. That makes the first-capture workflow feel broken.

Suggested implementation: Centralize AI readiness so the queue and UI agree. Include non-empty model selection in the queue's provider-configured check, while preserving local-provider behavior where an API key is not required. Consider reusing/moving `AIConfig.isConfigured` into `JobhuntCore` or adding a core-level readiness helper that both app UI and queue wiring call.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Queued extraction work with an empty `llmModel` emits `.providerNotConfigured` and remains queued instead of marking requests failed or auto-pausing.
- [x] #2 Hosted providers still require a non-empty API key and non-empty model before processing starts.
- [x] #3 Local providers such as LM Studio require a non-empty model but do not require an API key.
- [x] #4 The UI banner/service-status readiness and queue readiness use the same rule or share the same core helper to prevent future drift.
- [x] #5 Focused tests cover empty-model behavior for at least the default local provider and one hosted provider.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added core AIReadiness as the single readiness rule (model selected AND, for key-requiring providers, a key present) and routed both the queue's isProviderConfigured gate (AppServices) and the UI's AIConfig through it. Empty llmModel is now "not configured" for every provider, so the queue hits the existing not-configured path (QueueActor:319): emits .providerNotConfigured once and breaks, leaving requests queued — instead of running and failing with noModelSelected / auto-pausing. requiresAPIKey covers the same {openai,anthropic,google,openrouter} set AIConfig hardcoded, so the key behaviour is unchanged. AIReadinessTests cover empty-model for a local (lmstudio) and hosted (openai) provider plus the key gate. Commit fd9f35c.
<!-- SECTION:FINAL_SUMMARY:END -->
