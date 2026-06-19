---
id: TASK-546
title: 'Restore: quiesce runtime services before replacing the live SwiftData store'
status: To Do
assignee: []
created_date: '2026-06-19 22:17'
labels:
  - audit
  - backup
  - restore
  - persistence
  - runtime
dependencies: []
references:
  - app/Views/Settings/SettingsTab.swift
  - core/Services/BackupService.swift
  - app/Shell/AppServices.swift
  - core/LLM/QueueActor.swift
  - core/Services/AvailabilityChecker.swift
  - CLAUDE.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: normal Settings restore creates a safety backup, calls `BackupService.restore(from:to:)`, shows a completion alert, and then terminates. During the restore, the app's runtime services and the existing SwiftData container are still live: the LLM queue, availability loop, local server, and SettingsStore/ModelContext may still have open connections or pending writes against the same SQLite store files being moved aside and replaced.

Why this matters: restore is a file-boundary operation on the app's single-writer SQLite store. Replacing the store while background actors or the live container can still write risks WAL/state races, failed rollback assumptions, or writes landing in the old moved-aside file after the replacement has been staged. The project docs explicitly treat the store as single-writer and require external migrator operations to run with the app quit; in-app restore needs an equivalent quiesce boundary.

Suggested implementation: make the restore flow asynchronous and stop runtime work before the destructive swap. Call an app-owned shutdown/quiesce method that cancels queue/availability runtime tasks, stops the local server, and prevents new capture/queue work before `BackupService.restore`. Consider performing restore from a minimal relaunch/helper mode if fully closing the live SwiftData container cannot be guaranteed. Keep the pre-restore backup before the swap, but ensure no background writer is active between backup and replacement.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings restore stops or quiesces runtime services before calling `BackupService.restore`.
- [ ] #2 No LLM queue, availability auto-check, or local-server capture handling can write to the live store during the restore window.
- [ ] #3 The restore flow remains failure-safe: if restore fails, the app reports the error and does not leave runtime partially running against an unknown store state.
- [ ] #4 The app still terminates/relaunches after a successful restore so the new store is opened cleanly.
- [ ] #5 Tests or a seam verify the quiesce method is invoked before the restore operation.
- [ ] #6 Documentation/comments describe the restore boundary consistently with the single-writer store guidance.
<!-- AC:END -->
