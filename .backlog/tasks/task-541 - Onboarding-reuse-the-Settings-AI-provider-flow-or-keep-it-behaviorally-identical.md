---
id: TASK-541
title: >-
  Onboarding: reuse the Settings AI provider flow or keep it behaviorally
  identical
status: To Do
assignee: []
created_date: '2026-06-19 07:29'
labels:
  - audit
  - ux
  - onboarding
  - llm
  - settings
dependencies: []
references:
  - app/Views/Onboarding/OnboardingView.swift
  - app/Views/Settings/SettingsView.swift
  - app/Views/Settings/LLMConsentSheet.swift
  - core/Settings/ConsentHelper.swift
  - core/LLM/AIReadiness.swift
  - tests/AppUITests/MockLLMUITests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: onboarding's AI provider step has drifted from the Settings AI tab. Settings handles custom loopback vs remote custom differently for API-key requirements, re-prompts consent when a custom base URL becomes remote, guards Test Connection when no model is selected, trims API-key whitespace for model fetches, and protects slow model-fetch results from clobbering a newer provider selection. Onboarding implements a separate copy of this flow: `custom` always needs an API key, remote custom does not trigger the same consent path, Test Connection sends an empty model, and fetch results are not tied to the provider that started the request.

Why this matters: first-run setup is where users establish the LLM trust and readiness boundary. If onboarding makes different consent/API-key/model decisions than Settings, a user can finish onboarding with settings that behave differently later, or get confusing provider errors that Settings already fixed. This is knowledge duplication in a high-friction workflow.

Suggested implementation: extract a shared AI provider form/view-model used by both onboarding and Settings, or make onboarding call the same readiness/consent/model-fetch helpers as Settings. Keep onboarding visually compact if needed, but share the behavioral rules: custom remote consent, custom loopback keylessness, no-model test guard, API-key trimming, provider-scoped fetch results, and per-provider remembered model behavior if desired.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Onboarding and Settings use the same logic for whether a provider requires an API key.
- [ ] #2 Remote custom endpoints in onboarding require explicit consent before job/resume data can be sent; loopback custom endpoints do not.
- [ ] #3 Onboarding Test Connection fails fast with the same clear no-model message used by Settings.
- [ ] #4 Onboarding model fetches cannot overwrite the model list or model selection after the user switches providers.
- [ ] #5 API keys entered during onboarding are trimmed consistently with Settings before storage/use.
- [ ] #6 Tests cover at least custom loopback, remote custom consent, empty-model Test Connection, and provider-switch-during-fetch behavior.
<!-- AC:END -->
