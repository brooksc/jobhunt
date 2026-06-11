---
id: TASK-175
title: 'Settings: Remember or default LLM models per provider'
status: Done
assignee: []
created_date: '2026-06-11 22:12'
updated_date: '2026-06-11 22:30'
labels:
  - audit
  - settings
  - llm
dependencies: []
references:
  - core/Settings/SettingsStore.swift
  - core/LLM/LLMProviderFactory.swift
  - app/Views/Settings/SettingsView.swift
  - app/Views/Onboarding/OnboardingView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app stores one global `llmModel` value and passes it to every provider. The default model is LM Studio-specific, so switching to OpenAI, Anthropic, Google, OpenRouter, or custom providers can send an incompatible model unless the user manually changes it each time. Store provider-specific model choices or apply provider-specific defaults during provider switches.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Switching providers selects a valid default model or restores that provider’s last model choice.
- [ ] #2 Changing a model for one provider does not unintentionally overwrite another provider’s saved model choice unless explicitly intended.
- [ ] #3 Tests cover provider switching and provider-specific model persistence/defaulting.
<!-- AC:END -->
