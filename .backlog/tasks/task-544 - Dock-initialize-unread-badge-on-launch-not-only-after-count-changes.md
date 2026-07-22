---
id: TASK-544
title: 'Dock: initialize unread badge on launch, not only after count changes'
status: Done
assignee: []
created_date: '2026-06-19 07:30'
updated_date: '2026-07-22 00:47'
labels:
  - audit
  - ux
  - dock
  - notifications
  - unread
dependencies: []
references:
  - app/Platform/DockBadgeUpdater.swift
  - app/ContentView.swift
  - app/Platform/PlatformIntegration.swift
  - tests/CoreTests/JobServiceMutationTests.swift
priority: low
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `DockBadgeUpdater` sets `NSApp.dockTile.badgeLabel` only in `.onChange(of: unreadCount)`. `ContentView` passes `unreadJobs.count` from a SwiftData query. If the app launches with existing unread jobs, the initial count may never be written to the Dock badge until the unread count changes during that session.

Why this matters: unread jobs are used as the app's “ready to review” signal after extraction. A stale or missing Dock badge on launch weakens that workflow and can make previously processed jobs look reviewed when they are not.

Suggested implementation: set the badge on first appearance as well as on changes, ideally through one small helper so the empty/non-empty mapping is defined once. Add a test seam if direct `NSApp.dockTile` verification is awkward, or isolate badge-label formatting into a pure function and smoke-test the view lifecycle manually/UI-side.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When `ContentView` appears with `unreadCount > 0`, the Dock badge is set immediately.
- [ ] #2 When `ContentView` appears with zero unread jobs, any stale Dock badge is cleared.
- [ ] #3 Subsequent unread count changes continue to update the badge as before.
- [ ] #4 Badge formatting remains unchanged for positive counts.
- [ ] #5 Verification covers initial nonzero and initial zero states through a seam, pure helper, or UI/lifecycle test.
<!-- AC:END -->
