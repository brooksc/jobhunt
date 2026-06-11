---
id: TASK-124
title: 'Privacy: Enforce cloud LLM consent in the provider execution path'
status: To Do
assignee: []
created_date: '2026-06-11 03:01'
updated_date: '2026-06-11 04:33'
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
- [ ] #6 Custom provider consent is based on the configured base URL: loopback/on-device endpoints may be auto-consented, while remote custom URLs require explicit consent before any prompt is sent.
- [ ] #7 Settings and onboarding label Custom as local only when the configured endpoint is loopback/on-device; remote endpoints show equivalent disclosure to cloud providers.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Security/privacy audit addendum: `ConsentHelper` currently treats `custom` as a local provider, while `CustomProvider` sends prompts to the configured base URL. Remote custom endpoints can therefore receive job/resume text without the same cloud-provider consent path.
<!-- SECTION:NOTES:END -->
