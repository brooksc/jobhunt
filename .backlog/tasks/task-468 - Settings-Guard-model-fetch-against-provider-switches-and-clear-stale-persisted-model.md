---
id: TASK-468
title: >-
  Settings: Guard model-fetch against provider switches and clear stale
  persisted model
status: To Do
assignee: []
created_date: '2026-06-15 03:38'
labels:
  - bug
  - settings
  - app
dependencies: []
references:
  - app/Views/Settings/SettingsView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two related issues in SettingsView model handling:

1. `fetchModels()` (SettingsView.swift:414-436) has no in-flight provider guard. `applyProviderChange`/`syncFromSettings` fire `Task { await fetchModels() }` on every provider switch without cancelling the previous fetch, and on completion `fetchedModels = models` is assigned unconditionally. A slow fetch for provider A resolving after the user switches to provider B overwrites B's picker. Fix: capture the provider id at call start and re-check `guard provider == selectedProviderID else { return }` before assigning (or cancel the previous Task).

2. When the remembered model isn't in the freshly fetched list, `fetchModels()` sets `modelText = ""` to show the placeholder (SettingsView.swift:429-431), but the Picker's `onChange(of: modelText)` guards `!new.isEmpty` (:205-208), so `settings.llmModel` is never cleared. The UI shows "no model selected" while the persisted model still points at the unavailable model, which extraction/testConnection will use. Fix: when clearing modelText because the saved model vanished, also clear the persisted model for that provider.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A slow model fetch for a previous provider does not overwrite the current provider's model list
- [ ] #2 When the saved model is absent from the fetched list, the persisted settings.llmModel for that provider is cleared, not just the UI text
- [ ] #3 extraction/testConnection never run against a model the UI shows as unselected
<!-- AC:END -->
