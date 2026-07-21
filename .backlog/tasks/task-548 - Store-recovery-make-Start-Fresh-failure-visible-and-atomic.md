---
id: TASK-548
title: 'Store recovery: make Start Fresh failure-visible and atomic'
status: To Do
assignee: []
created_date: '2026-06-19 22:18'
updated_date: '2026-07-21 22:59'
labels:
  - audit
  - restore
  - recovery
  - persistence
  - ux
dependencies: []
references:
  - app/Views/Components/StoreRecoveryView.swift
  - core/Services/BackupService.swift
  - app/JobhuntApp.swift
priority: medium
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `StoreRecoveryView.startFresh()` moves the corrupt store and its WAL/SHM companions aside with `try?`, ignores every move failure, and terminates the app. If the store move fails because of permissions, a locked file, a missing parent directory issue, or a name collision, the app still quits and may relaunch into the same corrupt-store failure with no explanation.

Why this matters: Store recovery is a last-resort data-boundary workflow. The UI promises the corrupt store will be moved aside rather than deleted; if that cannot be done, the user needs a clear failure and should stay in recovery mode. Silent failure here turns a recovery action into a loop and weakens trust around data preservation.

Suggested implementation: make `startFresh()` perform explicit checked moves. Treat the main store move as required when the store exists; report an alert and do not quit if it fails. Move WAL/SHM companions best-effort only when present, but surface companion move failures if they could leave a stale SQLite sidecar next to the fresh store. Use a collision-resistant aside directory or UUID/timestamp path and ensure rollback/cleanup behavior is clear.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 If the main corrupt store cannot be moved aside, Start Fresh shows an error and does not terminate the app.
- [ ] #2 The recovery UI preserves the current promise that data is moved aside, not silently deleted.
- [ ] #3 WAL/SHM companion handling is explicit: missing companions are okay, move failures are either surfaced or safely cleaned up.
- [ ] #4 The aside destination cannot collide with an existing recovery file from the same second/session.
- [ ] #5 Successful Start Fresh still terminates/relaunches into a fresh store path.
- [ ] #6 Tests or a file-operation seam cover main-store move failure and successful move-aside behavior.
<!-- AC:END -->
