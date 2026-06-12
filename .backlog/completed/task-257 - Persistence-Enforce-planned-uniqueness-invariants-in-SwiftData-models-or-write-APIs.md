---
id: TASK-257
title: >-
  Persistence: Enforce planned uniqueness invariants in SwiftData models or
  write APIs
status: Done
assignee: []
created_date: '2026-06-12 02:50'
updated_date: '2026-06-12 03:09'
labels:
  - audit
  - persistence
  - data-integrity
dependencies: []
references:
  - swift-plan.md
  - core/Models/Capture.swift
  - core/Models/Job.swift
  - core/Models/Site.swift
  - core/Models/DuplicateDecision.swift
  - core/Models/DataQualityReview.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The project plan calls out unique `jobNumber`, capture hashes, site origins, duplicate-decision hashes, and one data-quality review per job, but current models only mark `Setting.key` and `SavedSearch.id` unique. Most uniqueness is enforced manually, if at all, which leaves direct writers and concurrent paths able to persist contradictory rows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each planned unique domain key has either a SwiftData uniqueness/index constraint or a documented single-writer invariant enforced by service tests.
- [ ] #2 File-backed tests prove duplicate `rawHash`, `jobNumber`, `Site.origin`, and `DuplicateDecision.cleanedHash` cannot create inconsistent persisted state.
- [ ] #3 Manual upsert paths are audited so bypassing one service cannot silently violate core invariants.
<!-- AC:END -->
