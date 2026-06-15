---
id: TASK-368
title: >-
  Schema evolution: Freeze historical schema snapshots before the next stored
  model change
status: Done
assignee: []
created_date: '2026-06-12 22:25'
updated_date: '2026-06-15 06:39'
labels:
  - audit
  - schema
  - migration
  - swiftdata
dependencies: []
references:
  - core/Models/Schema.swift
modified_files:
  - core/Models/Schema.swift
  - tests/CoreTests/SchemaEvolutionTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SchemaV1 is documented as frozen, but SchemaV1.models points directly at the live model classes. Any stored-property change mutates the historical V1 shape instead of preserving a migration source snapshot.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Before the next stored model change, introduce immutable schema snapshot types or an equivalent historical schema strategy.
- [ ] #2 JobhuntMigrationPlan uses ordered historical snapshots rather than only live model classes when a new schema version is added.
- [x] #3 Schema documentation and tests reflect the actual snapshot strategy.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Took the "equivalent historical schema strategy" option (AC#1's alternative) rather than pre-snapshotting all 16 live @Model classes into a frozen SchemaV1 namespace — doing that now is speculative (no V2 exists; a snapshot would be byte-identical to the live models) with real ongoing maintenance cost, conflicting with the simplicity-first guideline. Instead the V1 stored shape is frozen by compile-time tripwires: the existing testSchemaV1StoredPropertyNamesAreStable (catches rename/remove) plus a new testSchemaV1StoredPropertyTypesAreStable (binds every storage-critical property to an explicitly-typed let, so a TYPE change fails to compile). Schema.swift now documents this strategy under "How V1 is frozen without snapshot types" and points to the SchemaV2 process for when an actual breaking change lands.

REMAINING (AC#2, future-conditional): when SchemaV2 is added, snapshot the V1 models into a frozen namespace and make JobhuntMigrationPlan use ordered historical snapshots. Cannot be done until there is a V2. Left unchecked.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Now-actionable work complete: V1's stored shape is frozen via the compile-time name guard (testSchemaV1StoredPropertyNamesAreStable) + the new type guard (testSchemaV1StoredPropertyTypesAreStable), the "equivalent historical schema strategy" AC#1 allows, documented in Schema.swift's "How V1 is frozen without snapshot types" section (AC#1, AC#3). Deliberately did NOT pre-snapshot all 16 live @Model classes — speculative with no V2 (a snapshot would be byte-identical) and high maintenance. AC#2 (ordered historical snapshots) is future-conditional ("when a new schema version is added") and is carried forward in TASK-480, to be done at the first breaking model change. Closing here as the pre-V2 work is complete.
<!-- SECTION:FINAL_SUMMARY:END -->
