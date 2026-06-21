---
id: TASK-581
title: >-
  Dashboard: use unresolved duplicate-pair semantics for the Duplicates
  housekeeping card
status: To Do
assignee: []
created_date: '2026-06-21 03:11'
labels:
  - audit
  - dashboard
  - duplicates
  - workflow
dependencies: []
modified_files:
  - app/Views/Dashboard/DashboardView.swift
  - app/Views/Duplicates/DuplicatesView.swift
  - app/Shell/Sidebar.swift
  - core/Services/DuplicateDetector.swift
  - tests/CoreTests/DuplicateDetectorTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: Dashboard `duplicateCount` is `jobs.count(where: { $0.duplicateOfJobID != nil })`, while the Duplicates screen and sidebar badge count unresolved review pairs by running `DuplicateDetector.duplicateGroups` over unmarked jobs and resolved hashes. Marked duplicate jobs are intentionally resolved and excluded from the review queue, but the dashboard card still counts them and opens the Duplicates screen.

Why it matters: The dashboard can show a non-zero Duplicates count that opens to an empty duplicate review screen. This duplicates a domain decision already encoded in `DuplicatesView` and `Sidebar`: the actionable unit is unresolved duplicate pairs, not historical rows marked duplicate.

Suggested implementation: Reuse the same duplicate-review count policy used by `Sidebar.refreshDuplicateCount` and `DuplicatesView.refreshPairsInBackground`, ideally as a shared helper/projection so dashboard, sidebar, and Duplicates screen cannot drift. If the dashboard should display historical marked duplicates, label it separately and do not route it to the unresolved review queue.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dashboard Duplicates count matches the Duplicates screen unresolved pair count for the same data set.
- [ ] #2 Jobs already marked `.duplicate` do not inflate the dashboard actionable duplicate count.
- [ ] #3 Resolved duplicate decisions suppress dashboard duplicate counts the same way they suppress DuplicatesView pairs.
- [ ] #4 Tests cover marked duplicate rows, unresolved pairs, and resolved-hash suppression through the shared count helper.
<!-- AC:END -->
