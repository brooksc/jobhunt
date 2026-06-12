---
id: TASK-241
title: 'Tests: Replace screenshot-test raw store copy with consistent SQLite backup'
status: Done
assignee: []
created_date: '2026-06-12 02:01'
updated_date: '2026-06-12 02:16'
labels:
  - tests
  - backup
  - recovery
dependencies: []
references:
  - scripts/screenshot-tests.sh
  - core/Services/BackupService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
scripts/screenshot-tests.sh copies only the main jobhunt.store file before UI tests. For a WAL-backed SQLite/SwiftData store, this may miss uncheckpointed data. Use BackupService/VACUUM INTO or otherwise capture a consistent store snapshot.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Screenshot test backup uses a consistent SQLite backup mechanism or only copies the store after ensuring WAL state is included/checkpointed.
- [ ] #2 The script documents whether the app must be closed before backup.
- [ ] #3 Old screenshot backups remain pruned safely.
- [ ] #4 A failed backup stops tests or clearly warns that production data is not protected.
<!-- AC:END -->
