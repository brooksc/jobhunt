---
id: TASK-212
title: 'Duplicates: Make duplicate detection incremental or query-bounded'
status: Done
assignee: []
created_date: '2026-06-12 00:41'
updated_date: '2026-06-12 02:08'
labels:
  - performance
  - duplicates
  - swiftdata
  - audit
dependencies: []
references:
  - app/Views/Duplicates/DuplicatesView.swift
  - core/Services/DuplicateDetector.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DuplicatesView loads all jobs and snapshots them on the main actor, then DuplicateDetector performs all-jobs grouping and O(N²)-style company clustering for candidate groups. This will degrade as captures grow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Duplicate candidate generation avoids full all-jobs recomputation for ordinary view refreshes.
- [ ] #2 Heavy duplicate scoring runs off the main actor with bounded inputs or cached projections.
- [ ] #3 Performance tests or benchmarks cover a large synthetic job dataset.
<!-- AC:END -->
