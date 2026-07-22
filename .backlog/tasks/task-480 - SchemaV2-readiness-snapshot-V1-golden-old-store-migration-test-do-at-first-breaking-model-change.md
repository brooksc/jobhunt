---
id: TASK-480
title: >-
  SchemaV2 readiness: snapshot V1 + golden old-store migration test (do at first
  breaking model change)
status: To Do
assignee: []
created_date: '2026-06-15 06:39'
updated_date: '2026-07-22 18:39'
labels:
  - schema
  - migration
  - swiftdata
  - deferred
dependencies: []
references:
  - core/Models/Schema.swift
  - tests/CoreTests/SchemaEvolutionTests.swift
priority: low
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Carries the future-conditional remainder of TASK-368/369, which can only be done when the first breaking stored-model change (SchemaV2) actually lands. Until then, V1 is protected by the compile-time name+type stability guards in SchemaEvolutionTests (see TASK-368/369 final summaries). When SchemaV2 is introduced: (1) snapshot the V1 models into a frozen namespace and make JobhuntMigrationPlan use ordered historical snapshots rather than the live model classes (TASK-368 AC#2); (2) add a golden file-backed old-store (V1) fixture + a SchemaV1→SchemaV2 migration test asserting old rows survive and new fields get expected defaults (TASK-369 AC#1/#2); (3) follow the "How to add a SchemaV2" steps documented in Schema.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 V1 models snapshotted into a frozen namespace; JobhuntMigrationPlan uses ordered historical snapshots
- [ ] #2 Golden V1 old-store fixture committed and a V1→V2 migration test asserts data survives + new field defaults
- [ ] #3 Done as part of the first breaking schema change, not before
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Do not do SchemaV2 speculatively — only when there is a clear, concrete user benefit (2026-07-22).** Investigation found SchemaV2 currently unblocks nothing users want: additive changes (optional fields, new @Models) like appliedAt (TASK-504, shipped) and structured interview/offer tracking (TASK-501) are lightweight in-place migrations that need NO schema version. The only thing forcing SchemaV2 is removing the vestigial Contact/CoverLetter @Models (TASK-500), which is pure code cleanup (0 rows in the live store) — not a feature or data win — and building the V1->V2 migration plumbing here (480) only pays off the day a genuinely breaking change (rename/retype/drop-required) actually lands. Per AC#3, do 480 as part of that first real breaking change, not before. Until then this is cost with no payoff — leave it parked.
<!-- SECTION:NOTES:END -->
