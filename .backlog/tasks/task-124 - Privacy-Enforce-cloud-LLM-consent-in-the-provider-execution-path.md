---
id: TASK-124
title: 'Privacy: Enforce cloud LLM consent in the provider execution path'
status: To Do
assignee: []
created_date: '2026-06-11 03:01'
labels:
  - privacy
  - llm
  - settings
  - consent
dependencies: []
references:
  - core/LLM/LLMProviderFactory.swift
  - core/LLM/QueueActor.swift
  - core/Settings/ConsentHelper.swift
  - app/Views/Settings/SettingsView.swift
  - app/Views/Onboarding/OnboardingView.swift
  - tests/CoreTests/SettingsStoreTests.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cloud-provider consent is present in UI/onboarding, but the audit did not find enforcement immediately before outbound provider calls. Consent should fail closed at the queue/provider boundary, not only at configuration time.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every cloud LLM request checks provider-specific consent immediately before sending job or resume data.
- [ ] #2 Local-only providers remain auto-consented according to ConsentHelper behavior.
- [ ] #3 Queue processing fails closed with a user-visible recoverable state when consent is missing.
- [ ] #4 Tests prove cloud providers are blocked without consent and allowed after consent is recorded.
- [ ] #5 The consent enforcement path is not bypassable by direct QueueActor or provider factory usage.
<!-- AC:END -->
