---
id: TASK-320
title: 'Onboarding: Use canonical provider ID for Apple Intelligence'
status: To Do
assignee: []
created_date: '2026-06-12 20:01'
labels:
  - audit
  - llm-provider
  - onboarding
dependencies: []
references:
  - app/Views/Onboarding/OnboardingView.swift
  - app/Views/Settings/SettingsView.swift
  - core/LLM/LLMProviderFactory.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Onboarding saves Apple Intelligence with provider ID apple, but Settings and LLMProviderFactory use foundation_models. Selecting Apple Intelligence during onboarding falls through to the default LM Studio provider instead of FoundationModelsProvider.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Onboarding and Settings use the same canonical provider ID for Apple Intelligence.
- [ ] #2 LLMProviderFactory resolves the onboarding-selected Apple Intelligence provider to FoundationModelsProvider.
- [ ] #3 Regression tests or UI coverage verify onboarding selection persists and loads the expected provider.
<!-- AC:END -->
