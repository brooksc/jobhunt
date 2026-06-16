---
id: TASK-372
title: 'Store opening: Add preflight or migration repair for uniqueness constraints'
status: Done
assignee: []
created_date: '2026-06-12 22:26'
updated_date: '2026-06-16 06:02'
labels:
  - audit
  - schema
  - migration
  - data-safety
dependencies: []
references:
  - core/Models/Job.swift
  - core/Models/Capture.swift
  - core/Models/ModelContainerFactory.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several models document that duplicate rows must be removed before opening with unique constraints active, but production container creation opens the store directly. Future uniqueness constraints need a safe preflight or custom migration path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Document and implement a preflight/custom-migration strategy before adding additional uniqueness constraints to existing fields.
- [x] #2 Existing unique-constrained fields have a recovery story for stores containing duplicate legacy rows.
- [x] #3 File-backed tests cover duplicate legacy data and expected repair or recovery behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added a recovery path + documented strategy for unique constraints on existing fields. AC#1: documented the strategy in `ModelContainerFactory` — SwiftData enforces `.unique` via a SQLite index that fails to create on a store with pre-existing duplicates, so `ModelContainer(...)` throws and the app fails *closed* to `StoreRecoveryView`; before adding any new unique constraint, ship a one-shot migrator dedup mode run out-of-band (never auto-dedup on launch, per the one-time-ops-in-CLI convention). AC#2: implemented `JobhuntMigrator --repair-duplicate-job-numbers` (`tools/migrator/RepairJobNumbers.swift`) — raw-SQLite (a dup store can't be opened by SwiftData) that renumbers duplicate `ZJOBNUMBER` rows keeping the oldest (smallest Z_PK) and reassigning collisions to fresh `max+1`; non-destructive, idempotent, NULL-safe, column discovered via PRAGMA. Wired Mode/arg/main + README. AC#3: file-backed RepairJobNumbersTests (compiled into CoreTests) cover renumber-keeping-oldest with all rows preserved + unique, no-op on clean data, NULL-jobNumber ignored, and idempotency. Full CoreTests (770) green; migrator + app build. Note: app-created data can't collide (atomic ingest under the single-writer store), so this recovers externally-modified/legacy/pre-constraint stores.
<!-- SECTION:FINAL_SUMMARY:END -->
