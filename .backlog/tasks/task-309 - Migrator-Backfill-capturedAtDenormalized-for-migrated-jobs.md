---
id: TASK-309
title: 'Migrator: Backfill capturedAtDenormalized for migrated jobs'
status: To Do
assignee: []
created_date: '2026-06-12 19:34'
labels:
  - audit
  - migration
  - persistence
dependencies: []
references:
  - tools/migrator/Migration.swift
  - tools/migrator/Patch.swift
  - app/Views/Jobs/JobsSortLogic.swift
  - core/Models/SavedSearch.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The standalone migrator links Job.capture but does not set Job.capturedAtDenormalized from Capture.capturedAt. Jobs, saved searches, and availability checks use capturedAtDenormalized with createdAt fallback, so migrated rows can sort/filter by the wrong date.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Migration and patch paths set Job.capturedAtDenormalized from the linked capture's capturedAt when available.
- [ ] #2 Migrator tests verify capturedAtDenormalized is populated and differs from createdAt when fixture data differs.
- [ ] #3 Existing stores with nil capturedAtDenormalized have a documented repair path or patch command.
<!-- AC:END -->
