---
id: TASK-686
title: Extract application-milestone persistence from BackgroundStore
status: Done
assignee: []
created_date: '2026-08-21 20:41'
updated_date: '2026-08-22 20:48'
labels:
  - architecture
  - persistence
  - tech-debt
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Models
priority: medium
type: enhancement
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackgroundStore is a broad change hub spanning unrelated domains. Reduce its regression radius with one bounded extraction for application milestones: referral attempts, interviews, offers, their timeline events, and related cleanup. Preserve existing data behavior and actor isolation while giving this workflow a cohesive persistence boundary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Referral-attempt, interview, and offer persistence is owned by a cohesive boundary rather than BackgroundStore
- [x] #2 Timeline-event creation, update, deduplication, and deletion remain transactionally consistent with their owning records
- [x] #3 Existing callers use the new boundary without duplicating milestone persistence rules
- [x] #4 No persisted schema or migration is required for this extraction
- [x] #5 Existing milestone behavior remains compatible for the app, server, MCP, and migration tools
- [x] #6 Automated tests cover create, update, delete, missing-job, deduplication, and rollback behavior for each extracted record type
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`MilestonePersistence` (core/Services/MilestonePersistence.swift) now owns referral outreach, interview rounds, offers, and the timeline events mirroring each — 283 lines out of BackgroundStore, which is the file every other domain writes through.

**The transaction deliberately did not move (#2).** The functions take the caller's `ModelContext` and never save; BackgroundStore's methods remain the entry points and own the `save()`. A second `@ModelActor` would have read as the tidier extraction and been the wrong one: the SQLite store is single-writer, and a second context would have split precisely the record↔event pairing this exists to protect. Deletes return `Bool` so a caller can skip a save that would write nothing.

**#3/#4/#5** No caller changed, no public API changed, no schema or migration involved — app, server, MCP and the migrator all reach the same `BackgroundStore` methods as before.

**#6** The existing end-to-end suites (`MilestoneStoreTests`, `ReferralStoreTests` — 24 tests over create, update, delete, missing-job and deduplication) carry the behaviour unchanged and all pass. `MilestonePersistenceTests` adds what only the new boundary can be asked: nothing commits until the caller saves, a record and its event land in the same save, a write against a missing job leaves nothing to unwind, and an absent delete reports no work.

Gate green: 1902 CoreTests + 58 ServerTests + 28 MCPTests, coverage 87.70%, swiftlint/swiftformat clean.
<!-- SECTION:FINAL_SUMMARY:END -->
