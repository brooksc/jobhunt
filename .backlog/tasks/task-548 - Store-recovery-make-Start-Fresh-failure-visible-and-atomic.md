---
id: TASK-548
title: 'Store recovery: make Start Fresh failure-visible and atomic'
status: Done
assignee: []
created_date: '2026-06-19 22:18'
updated_date: '2026-08-09 20:16'
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
- [x] #1 If the main corrupt store cannot be moved aside, Start Fresh shows an error and does not terminate the app.
- [x] #2 The recovery UI preserves the current promise that data is moved aside, not silently deleted.
- [x] #3 WAL/SHM companion handling is explicit: missing companions are okay, move failures are either surfaced or safely cleaned up.
- [x] #4 The aside destination cannot collide with an existing recovery file from the same second/session.
- [ ] #5 not verified (visual): a successful Start Fresh still terminates — the NSApp.terminate call is unchanged and only reached on success, but the relaunch-into-fresh-store path was not observed, since driving the UI is out of scope for this run.
- [x] #6 Tests cover main-store move failure and successful move-aside behaviour via a file-operation seam.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`StoreQuarantine.moveAside` in JobhuntCore replaces four `try?` calls followed by an unconditional `NSApp.terminate`. The view now stays in recovery and shows the error when the move fails, instead of quitting into the same corrupt store with nothing said.

**Companions are handled explicitly, and not the way the task's wording suggests.** It proposed surfacing companion move failures. Surfacing alone isn't enough: a `-wal` left beside a brand-new store is not inert — SQLite may try to replay it into a database it doesn't belong to. So an unmovable companion is *deleted*, since the data it belonged to has already left with the main store; only a companion that can be neither moved nor deleted is reported, and the view then warns rather than relaunching.

**Collision resistance:** UTC timestamp plus a short UUID. Seconds alone collide when recovery is retried inside the same second — which is exactly when someone retries it.

**Testability seam:** an injectable `FileOps` struct rather than hitting the disk, so the failure paths (permission denied on the store, on the `-wal`, on both move and delete) are exercised directly instead of requiring a locked file.

**Tests** (`StoreQuarantineTests`, 8): a failed main move throws and never falls back to deleting the user's data; the store is moved not removed; companions move alongside; missing companions are fine; an unmovable `-wal` is deleted; one that can't be removed either is reported; two recoveries in the same second get different destinations; a missing store is not an error.

Criterion 5 is `not verified` — the terminate call is unchanged and reached only on success, but the relaunch was not observed.
<!-- SECTION:FINAL_SUMMARY:END -->
