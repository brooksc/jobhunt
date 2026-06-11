---
id: TASK-105
title: Use one shared SettingsStore instance across app runtime
status: Done
assignee: []
created_date: '2026-06-10 20:49'
updated_date: '2026-06-11 01:42'
labels:
  - architecture
  - audit
  - settings
dependencies: []
references:
  - app/Shell/AppServices.swift
  - app/Views/Settings/SettingsView.swift
  - core/Settings/SettingsStore.swift
  - core/LLM/QueueActor.swift
  - core/LLM/LLMProviderFactory.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Architecture audit finding: `AppServices` creates a long-lived `SettingsStore` used by queue/provider code, while `SettingsView` creates another `SettingsStore` from `modelContext`. Because `SettingsStore` caches values, settings changes can persist but not update the instance used by runtime services. Make Settings UI use the same app-scoped settings service as queue and provider code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings UI receives and mutates the same `SettingsStore` instance created by `AppServices`.
- [ ] #2 Queue/provider behavior observes settings changes without requiring app restart or a separate cache refresh.
- [ ] #3 Any remaining ad hoc `SettingsStore(modelContext:)` construction in app views is removed or justified as test/demo-only.
- [ ] #4 Tests or a focused verification scenario confirms a settings change affects the provider factory or queue-facing settings path.
<!-- AC:END -->
