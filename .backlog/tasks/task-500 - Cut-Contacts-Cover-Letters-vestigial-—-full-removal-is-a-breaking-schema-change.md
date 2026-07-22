---
id: TASK-500
title: >-
  Cut Contacts & Cover Letters (vestigial — full removal is a breaking schema
  change)
status: On Hold
assignee: []
created_date: '2026-06-18 23:05'
updated_date: '2026-07-22 18:40'
labels:
  - cleanup
  - schema
  - tech-debt
dependencies: []
priority: low
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Contact and CoverLetter @Models + JobService CRUD exist but have ZERO UI (verified). Decision: cut them.

IMPORTANT caveat: they're wired into Job via @Relationship (Job.contacts, Job.coverLetters), so fully removing the @Model classes from SchemaV1 is a *breaking* SwiftData schema change — it can't be done as a casual edit and requires the first SchemaV2 + migration (ties into TASK-480). So scope this carefully:
- Phase A (safe, now-ish): remove the dead JobService CRUD methods (createContact/updateContact/deleteContact, deleteCoverLetter) and any references, IF unused, to shrink surface. Leave the models in place.
- Phase B (with SchemaV2): drop the Contact/CoverLetter models + Job relationships as part of the first breaking schema migration, with a golden migration test (TASK-480).

References: core/Models/Contact.swift, core/Models/CoverLetter.swift, core/Models/Job.swift (relationships), core/Services/JobService.swift, core/Models/Schema.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dead Contact/CoverLetter service methods removed (Phase A) without touching the schema
- [ ] #2 Model + relationship removal is scoped into the SchemaV2 migration work (Phase B), not done as a casual edit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Parked (2026-07-22): this is the only change forcing SchemaV2, but it's pure cleanup of unused models (0 Contact/CoverLetter rows in the live store) and drags in the full V1->V2 migration harness (TASK-480). Not worth doing on its own — avoid unless a genuinely breaking schema change lands that needs the migration plumbing anyway. See TASK-480 notes.
<!-- SECTION:NOTES:END -->
