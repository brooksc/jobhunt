---
id: TASK-543
title: 'UI: deep-link provider-not-configured notifications to the AI settings tab'
status: Done
assignee: []
created_date: '2026-06-19 07:29'
updated_date: '2026-06-19 23:33'
labels:
  - audit
  - ux
  - notifications
  - llm
  - settings
dependencies: []
references:
  - app/Platform/PlatformIntegration.swift
  - app/Shell/Router.swift
  - app/Views/Settings/SettingsView.swift
  - app/ContentView.swift
  - app/Views/Components/AIConfigBanner.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: when queued work has no usable AI provider, `PlatformIntegration` posts a `provider-not-configured` notification with `userInfo: ["navigate": "settings"]`. The notification click handler opens the Settings window via `showSettingsWindow:`, but it does not set `router.settingsTab = .llm`. Other setup paths, such as the toolbar service menu and `AIConfigBanner`, explicitly select the AI tab before opening Settings.

Why this matters: the notification title says “Set up an AI provider,” so clicking it should land on the exact configuration surface. Opening the last-used or default Settings tab adds avoidable friction at the moment the user is trying to unblock queued work.

Suggested implementation: distinguish generic settings navigation from AI-provider setup navigation. For example, use `userInfo: ["navigate": "settings", "settingsPane": "llm"]` or a dedicated `navigate: "aiSettings"` value, set `router.settingsTab = .llm`, then open Settings. Keep existing generic Settings behavior available for other notifications if needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Clicking the provider-not-configured notification opens Settings with the AI tab selected.
- [ ] #2 Generic settings notification navigation, if any, remains possible without always forcing the AI tab.
- [ ] #3 Toolbar and AIConfigBanner setup paths continue to select the same AI tab.
- [ ] #4 A focused test/seam verifies the notification userInfo maps to `router.settingsTab = .llm`.
- [ ] #5 The notification copy still clearly explains queued AI work is blocked by missing provider setup.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Done as part of the TASK-542 auth-error work (commit 7434166). The notification deep-link for AI-related nudges now selects the AI Provider (.llm) tab: PlatformIntegration's didReceive handles a "settings-ai" navigate value by setting router.settingsTab = .llm before opening the Settings window, and both the provider-not-configured notification and the new auth-key-rejected notification use it. Previously provider-not-configured opened Settings on whatever tab was last shown.
<!-- SECTION:FINAL_SUMMARY:END -->
