---
id: TASK-541
title: >-
  Onboarding: reuse the Settings AI provider flow or keep it behaviorally
  identical
status: Done
assignee: []
created_date: '2026-06-19 07:29'
updated_date: '2026-06-20 03:48'
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
- [x] #1 Onboarding and Settings use the same logic for whether a provider requires an API key.
- [x] #2 Remote custom endpoints in onboarding require explicit consent before job/resume data can be sent; loopback custom endpoints do not.
- [x] #3 Onboarding Test Connection fails fast with the same clear no-model message used by Settings.
- [x] #4 Onboarding model fetches cannot overwrite the model list or model selection after the user switches providers.
- [x] #5 API keys entered during onboarding are trimmed consistently with Settings before storage/use.
- [x] #6 Tests cover at least custom loopback, remote custom consent, empty-model Test Connection, and provider-switch-during-fetch behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Extracted a shared AIProviderFormModel (Core, @Observable, no SwiftUI) as the single source of truth for the AI-provider form, and rewired BOTH the onboarding step and the Settings AI tab onto it so they can no longer drift.

The model encodes the canonical Settings behavior the onboarding copy had drifted from:
- AC#1: custom **loopback** needs no API key; custom **remote** does (`needsAPIKey` uses ConsentHelper.isLoopbackURL).
- AC#2: switching to any non-consented provider requires consent, and a custom URL becoming **remote** triggers consent (onBaseURLChanged); loopback custom does not.
- AC#3: Test Connection fails fast with a clear "select a model" message when no model is set (and maps 401/403 via httpFailureMessage).
- AC#4: model fetches are provider-scoped — a slow fetch that resolves after the user switched providers is discarded.
- AC#5: API keys are whitespace-stripped as typed.
- Per-provider remembered model via setModelForProvider.

AC#6: AIProviderFormModelTests (CoreTests, 7 tests) covers custom-loopback vs remote key/consent, switch-to-unconsented-cloud deferral, empty-model Test Connection, the provider-switch-during-fetch race (via an injected model lister), API-key trimming, and the 401 message. The model fetcher is injectable specifically to make the race testable.

Views keep their own layout: onboarding (cpu header, LM Studio download + "Get API key" links) and Settings (pricing + cost-estimate, OpenRouter rotation, timeout, keychain/no-model hints, a11y ids); both drive the consent sheet via .sheet(item: model.pendingConsent). Removed Settings' now-orphaned private ProviderOption/ConsentRequest + duplicate logic.

Commits: 8a3f66e→cb82f2a (model+tests), 0c5ec53 (onboarding), 172688c (Settings). Build + fast gate + lint green.
<!-- SECTION:FINAL_SUMMARY:END -->
