---
id: TASK-522
title: >-
  Persistence: align unique-constraint repair strategy with all unique SwiftData
  fields
status: To Do
assignee: []
created_date: '2026-06-19 03:56'
labels:
  - audit
  - persistence
  - schema
  - migrator
  - data-integrity
dependencies: []
references:
  - core/Models/ModelContainerFactory.swift
  - core/Models/Job.swift
  - core/Models/Capture.swift
  - core/Models/Site.swift
  - core/Models/Setting.swift
  - core/Models/DuplicateDecision.swift
  - core/Models/SavedSearch.swift
  - tools/migrator/RepairJobNumbers.swift
  - tools/migrator/README.md
  - tests/CoreTests/RepairJobNumbersTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: the uniqueness strategy comment in `ModelContainerFactory` says `jobNumber` is the only unique field today, but the model layer also declares unique constraints on fields such as `Capture.rawHash`, `Site.origin`, `Setting.key`, `DuplicateDecision.cleanedHash`, and `SavedSearch.id`. Only duplicate `jobNumber` has a raw-SQL pre-open repair path documented and tested.

Why this matters: SwiftData creates SQLite unique indexes during store open. If an existing or externally modified store contains duplicate values for any unique field, the app can fail before a `ModelContainer` opens. Recovery then falls back to restore/start-fresh instead of offering a targeted non-destructive repair, and the documented strategy understates the actual risk surface.

Suggested implementation: inventory every `@Attribute(.unique)` field and decide per field whether duplicates are impossible, should be diagnosed only, or should have a raw-SQL repair mode that can run before SwiftData opens the store. Update the uniqueness strategy documentation and migrator README accordingly. Where repair is appropriate, implement idempotent raw-SQL repair with file-backed tests similar to duplicate job number repair.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The uniqueness strategy documentation lists every current unique field and its repair/diagnostic policy.
- [ ] #2 The migrator README explains how to recover from duplicate unique values for every field that can block store open.
- [ ] #3 Fields that need pre-open repair have idempotent raw-SQL repair or diagnostic coverage that does not require `ModelContainer` to open first.
- [ ] #4 File-backed tests cover at least one duplicate case for each implemented repair/diagnostic path.
- [ ] #5 Existing duplicate job number repair behavior remains unchanged.
<!-- AC:END -->
