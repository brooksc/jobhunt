---
id: TASK-552
title: Include settings and keychain persistence failures in copied diagnostics
status: Done
assignee: []
created_date: '2026-06-19 22:59'
updated_date: '2026-06-26 00:50'
labels:
  - audit
  - diagnostics
  - supportability
  - settings
dependencies: []
references:
  - 'app/Views/Settings/DebugTab.swift:128'
  - 'app/Views/Settings/DebugTab.swift:193'
  - 'core/Settings/SettingsStore.swift:44'
modified_files:
  - app/Views/Settings/DebugTab.swift
  - core/Settings/SettingsStore.swift
  - tests/CoreTests/DiagnosticsRedactorTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: the Debug tab renders a Settings Error section from `settings.lastSettingsError` (`app/Views/Settings/DebugTab.swift:128`), and `SettingsStore` separately tracks keychain write failures, SwiftData persist failures, and load failures (`core/Settings/SettingsStore.swift:44`). However, `buildDiagnosticsText` includes LLM settings, server status, queue counts, and recent toast errors, but it does not include `lastSettingsError`, `keychainWriteError`, or `loadError` (`app/Views/Settings/DebugTab.swift:193`).

Why important: settings persistence and keychain failures directly affect AI provider setup, onboarding state, backup/restore behavior, and user preferences. When a user copies diagnostics for support, the bundle can omit the exact state that explains why a preference or API key did not stick. Since these fields are already designed to avoid raw setting values, adding redacted versions improves supportability without adding job/resume content.

Suggested implementation: add a `Settings` or `Persistence` section to copied diagnostics that includes `lastSettingsError`, `keychainWriteError`, and `loadError` when present, each passed through `DiagnosticsRedactor.redact`. Keep empty-state output compact, e.g. `(none)`. Add focused coverage if `buildDiagnosticsText` becomes testable; otherwise add a lightweight helper that formats diagnostics sections and can be unit tested.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Copied diagnostics include settings persist, keychain write, and settings load errors when present.
- [x] #2 All included settings/keychain diagnostic text is passed through `DiagnosticsRedactor.redact`.
- [x] #3 The diagnostics output still excludes raw setting values, API keys, job descriptions, and resume content.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DiagnosticsReport gained a "Settings / Persistence" section carrying lastSettingsError, keychainWriteError, and loadError when present (each redacted; "(none)" when clean). AppServices.diagnosticsText passes them from SettingsStore. No raw setting values, API keys, job, or resume content are included. Tests: DiagnosticsReportTests.testIncludesRedactedSettingsErrorsWhenPresent / testSettingsSectionShowsNoneWhenClean. Commit 456ec97.
<!-- SECTION:FINAL_SUMMARY:END -->
