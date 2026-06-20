---
id: TASK-576
title: >-
  Needs Action: share one visible-follow-up predicate for badges, dashboard,
  detail, export, and list
status: To Do
assignee: []
created_date: '2026-06-20 22:54'
labels:
  - audit
  - needs-action
  - follow-ups
  - workflow
dependencies: []
modified_files:
  - core/Models/JobAction.swift
  - app/Views/Needs/NeedsActionView.swift
  - app/Shell/Sidebar.swift
  - app/Views/Dashboard/DashboardView.swift
  - app/Views/Detail/JobDetailView.swift
  - core/Services/ExportService.swift
  - tests/CoreTests/JobServiceMutationTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: The app has several definitions of an actionable follow-up. `NeedsActionView` shows only incomplete actions that are not snoozed into the future and that still have a linked job. The sidebar badge queries every `JobAction` with `completedAt == nil`, so future-snoozed or orphaned actions can inflate the badge while the Needs Action screen says there are no follow-ups. Dashboard and detail use similar but independently written filters, while export counts every incomplete action regardless of snooze state.

Why it matters: The same domain concept, 'needs action', is encoded in multiple places. Users can see a sidebar badge or exported pending-action count that does not match the screen they open. Future changes to snooze semantics, orphan handling, or terminal-job handling will require shotgun edits across views and services.

Suggested implementation: Add a shared pure predicate/snapshot for actionable follow-ups, for example `FollowUpVisibility.isActionable(action, now:)` and a separate `isOpenForExport` if export intentionally means broader lifecycle state. Use it from `NeedsActionView`, `Sidebar`, `DashboardDerived`, `DetailFooter`/`TimelineTabView`, and `ExportService`, or explicitly name the broader variants so UI badge semantics cannot drift from list semantics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sidebar Needs Action badge matches the number of actions visible in Needs Action with no filters applied.
- [ ] #2 Future-snoozed actions do not contribute to the Needs Action badge while hidden from the Needs Action screen.
- [ ] #3 Actions without a linked job are either excluded consistently from all actionable UI or surfaced in a deliberate recovery view.
- [ ] #4 Dashboard follow-up section and job detail pending-action indicators use the same shared actionable predicate.
- [ ] #5 Tests cover active, completed, future-snoozed, and orphaned follow-up rows across the shared predicate.
<!-- AC:END -->
