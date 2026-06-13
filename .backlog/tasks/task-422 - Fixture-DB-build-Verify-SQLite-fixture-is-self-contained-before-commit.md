---
id: TASK-422
title: 'Fixture DB build: Verify SQLite fixture is self-contained before commit'
status: To Do
assignee: []
created_date: '2026-06-13 04:21'
labels:
  - audit
  - fixtures
  - sqlite
dependencies: []
references:
  - scripts/build-fixture-db.sh
  - core/Models/ModelContainerFactory.swift
  - docs/test-db-spec.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The fixture build script currently runs the app to write the main fixture file and checks only that the file exists. The fixture copy path opens only the main source DB file and does not copy source WAL/SHM companions. Without an explicit checkpoint/VACUUM/backup step and a validation reopen, a generated fixture can be stale or incomplete if recent writes remain in WAL files or if companion-file naming differs between cleanup paths.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The fixture build process produces a self-contained SQLite fixture that can be copied and opened without relying on WAL or SHM sidecar files.
- [ ] #2 The script validates the generated fixture by reopening a fresh copy with the app's SwiftData migration/schema configuration and checking expected fixture counts or manifest values.
- [ ] #3 Cleanup handles the companion-file naming patterns actually produced by SQLite/SwiftData for the configured store URL.
- [ ] #4 The build fails with a clear error if validation fails or sidecar state would be required to read the fixture.
- [ ] #5 Documentation states the fixture artifact policy for main DB and sidecar files.
<!-- AC:END -->
