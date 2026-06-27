---
id: TASK-568
title: 'Settings: align remote custom provider API-key readiness with the AI form'
status: Done
assignee: []
created_date: '2026-06-20 04:07'
updated_date: '2026-06-27 00:58'
labels:
  - audit
  - settings
  - llm
  - workflow
dependencies: []
modified_files:
  - core/LLM/AIProviderFormModel.swift
  - core/LLM/AIReadiness.swift
  - core/LLM/LLMProviderFactory.swift
  - tests/CoreTests/AIReadinessTests.swift
  - tests/CoreTests/AIProviderFormModelTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `AIProviderFormModel.needsAPIKey` treats a `custom` provider with a non-loopback base URL as key-requiring, but `LLMProviderFactory.requiresAPIKey(provider:)` returns false for every `custom` provider and `AIReadiness.isConfigured` has no base-URL input. This means the Settings/Onboarding form can show an API-key field for a remote custom endpoint while the shared readiness gate and queue still consider that provider configured with only a model.

Why it matters: The same provider setup rule is encoded differently in the form and the queue gate. A remote custom endpoint can be shown as incomplete in the form but complete to the setup checklist/queue, leading to failed provider calls that should have been blocked as configuration work.

Suggested implementation: Move the custom loopback vs remote key requirement into the shared readiness/provider policy. Give readiness enough context to evaluate `provider == "custom"` plus `llmBaseURL`, or add a policy helper such as `requiresAPIKey(provider:baseURL:)` and use it from both `AIProviderFormModel.needsAPIKey` and `AIReadiness`. Add tests for custom loopback no-key readiness and custom remote missing-key readiness.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Remote custom providers without an API key are not reported as configured when the form says they need a key.
- [x] #2 Custom loopback providers continue to be configurable with only a selected model and no API key.
- [x] #3 `AIProviderFormModel.needsAPIKey` and `AIReadiness` use the same shared provider policy instead of duplicating the decision.
- [x] #4 Tests cover `custom` loopback and `custom` remote readiness paths.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added LLMProviderFactory.requiresAPIKey(provider:baseURL:) — the single base-URL-aware policy: custom-loopback needs no key, custom-remote does, hosted always do, lmstudio doesn't. AIProviderFormModel.needsAPIKey and AIReadiness.isConfigured both call it, so the form and the readiness/queue gate agree: a remote custom endpoint without a key is now not-configured (AC#1), while custom-loopback stays configurable with just a model (AC#2). Single shared decision, no duplication (AC#3). Tests cover custom loopback (no key → configured) and custom remote (missing key → not configured) plus the shared policy directly (AC#4). Full CoreTests (951) green; lint clean. Commit c7fea75 (shared with TASK-567).
<!-- SECTION:FINAL_SUMMARY:END -->
