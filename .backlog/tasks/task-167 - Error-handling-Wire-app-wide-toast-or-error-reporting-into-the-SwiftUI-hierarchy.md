---
id: TASK-167
title: >-
  Error handling: Wire app-wide toast or error reporting into the SwiftUI
  hierarchy
status: To Do
assignee: []
created_date: '2026-06-11 21:42'
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
