---
id: TASK-112
title: 'macOS UX: Remove view-level main-window resizing from ContentView'
status: To Do
assignee: []
created_date: '2026-06-11 02:24'
labels:
  - ux
  - macos
  - windowing
  - swiftui
dependencies: []
references:
  - app/ContentView.swift
  - app/JobhuntApp.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ContentView.configureWindow()` reaches into `NSApp.mainWindow` on appear, sets a minimum size, and grows the window to at least 1200x750 even though the app scene already declares a default size. This view-level AppKit bridge can override user-restored window sizes and behave poorly with future multi-window support. Move window sizing policy into scene/window configuration and avoid resizing from content views.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `ContentView` no longer directly resizes `NSApp.mainWindow` during view appearance
- [ ] #2 Default and minimum window sizing are expressed through appropriate scene/window configuration or a narrowly scoped platform integration layer
- [ ] #3 User-resized windows are not forcibly enlarged on normal section navigation or view refresh
- [ ] #4 Launch behavior still provides a reasonable first-run window size
- [ ] #5 Manual verification or UI coverage documents launch and restored-window behavior
<!-- AC:END -->
