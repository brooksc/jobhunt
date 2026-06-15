---
id: TASK-468
title: >-
  Settings: Guard model-fetch against provider switches and clear stale
  persisted model
status: Done
assignee: []
created_date: '2026-06-15 03:38'
updated_date: '2026-06-15 18:06'
labels:
  - bug
  - settings
  - app
dependencies: []
references:
  - app/Views/Settings/SettingsView.swift
modified_files:
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
- [x] #1 A slow model fetch for a previous provider does not overwrite the current provider's model list
- [x] #2 When the saved model is absent from the fetched list, the persisted settings.llmModel for that provider is cleared, not just the UI text
- [x] #3 extraction/testConnection never run against a model the UI shows as unselected
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
fetchModels() now captures the provider at call start and re-checks `provider == selectedProviderID` before assigning fetchedModels/modelText in both success and catch paths, so a slow fetch for provider A can't overwrite B's picker after a switch (AC#1). When the remembered model isn't in the fetched list it now clears the persisted selection too via settings.setModelForProvider("", provider:) — not just modelText — so the UI's "unselected" state matches what extraction/testConnection use (the Picker's onChange guards !isEmpty and so never cleared the persisted value) (AC#2/#3). App builds; no unit test (SwiftUI async UI state).
<!-- SECTION:FINAL_SUMMARY:END -->
