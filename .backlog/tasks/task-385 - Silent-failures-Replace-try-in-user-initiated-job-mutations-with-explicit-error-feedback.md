---
id: TASK-385
title: >-
  Silent failures: Replace try? in user-initiated job mutations with explicit
  error feedback
status: Done
assignee: []
created_date: '2026-06-12 22:57'
updated_date: '2026-06-15 05:23'
labels:
  - audit
  - error-handling
  - ux
  - jobs
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/ContentView.swift
  - app/Views/Detail/JobDetailView.swift
modified_files:
  - app/Views/Jobs/JobsView.swift
  - app/ContentView.swift
  - app/Views/Detail/JobDetailView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Audit found many user-facing job commands that mutate data with `try?`, causing failures to look successful. Examples include re-running AI, status changes, archive/delete, mark applied, rating changes, fit-score enqueue, and duplicate unmarking. Deleting also clears selection before persistence succeeds. Replace these command paths with awaited error handling, user-visible feedback, and consistent state recovery.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Job mutation commands no longer use `try?` for persistence or queue operations.
- [x] #2 Failures show a user-visible error without implying the action succeeded.
- [x] #3 Delete/archive/status/rating/re-run/apply flows preserve or restore UI state when persistence fails.
- [x] #4 Bulk actions report partial failure summaries where applicable.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced try? on every user-initiated job mutation (set status, archive, delete, set rating, re-run AI/reset extraction, mark expired, apply + follow-up action, complete action, update fields, enqueue fit, unmark duplicate) across JobsView, ContentView, and JobDetailView with do/catch that shows an error toast via appServices.toastStore (isError:true) — which also records into the Debug tab's recent-errors log. Bulk loops report partial-failure summaries ("Couldn't X N of M"). markExpired's success toast now fires only on success (AC#2). The views are @Query-driven, so a failed persistence naturally leaves the unchanged store state visible rather than a misleading optimistic update (AC#3). The one automatic side-effect (markOpened on selection) logs instead of toasting. Added @Environment(AppServices.self) to the detail sub-views that lacked it; Task.sleep (not a mutation) left as try?. No unit tests (SwiftUI command wiring — would need XCUITest); verified by build.
<!-- SECTION:FINAL_SUMMARY:END -->
