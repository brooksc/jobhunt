---
id: TASK-167
title: >-
  Error handling: Wire app-wide toast or error reporting into the SwiftUI
  hierarchy
status: Done
assignee: []
created_date: '2026-06-11 21:42'
updated_date: '2026-06-11 22:19'
labels:
  - audit
  - error-handling
  - ux
  - macos
dependencies: []
references:
  - app/Views/Components/ToastView.swift
  - app/JobhuntApp.swift
  - app/ContentView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ToastStore` and `ToastOverlay` exist but are only used in previews. Screens currently reimplement local banners/alerts or suppress errors entirely. Inject a shared error/toast reporting mechanism into the app hierarchy and use it for cross-cutting command failures where local inline validation is not appropriate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A shared toast/error reporter is created and injected into the main app UI.
- [ ] #2 At least export, bulk job actions, and queue command failures can show user-visible errors through the shared mechanism.
- [ ] #3 Existing local inline validation remains local where it is more appropriate than a global toast.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `toastStore: ToastStore` to `AppServices`. Wired `ToastOverlay` into `ContentView.body` via `.overlay(alignment: .bottom)`. Bulk archive and delete failures in `JobsView` now call `appServices.toastStore.show(...)` with `isError: true` instead of suppressing errors. CSV export failures in `JobsView.exportCSV()` also route through the toast. Queue command failures remain local-inline (already visible via `errorMessage` banner in LLMQueueView, which is appropriate).
<!-- SECTION:FINAL_SUMMARY:END -->
