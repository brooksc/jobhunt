---
id: TASK-581
title: >-
  Dashboard: use unresolved duplicate-pair semantics for the Duplicates
  housekeeping card
status: Done
assignee: []
created_date: '2026-06-21 03:11'
updated_date: '2026-06-26 02:40'
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
- [x] #1 Dashboard Duplicates count matches the Duplicates screen unresolved pair count for the same data set.
- [x] #2 Jobs already marked `.duplicate` do not inflate the dashboard actionable duplicate count.
- [x] #3 Resolved duplicate decisions suppress dashboard duplicate counts the same way they suppress DuplicatesView pairs.
- [x] #4 Tests cover marked duplicate rows, unresolved pairs, and resolved-hash suppression through the shared count helper.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Dashboard duplicateCount now uses DuplicateDetector.unresolvedPairCount(jobs:decisions:) — the same unresolved-review-pair count the Duplicates screen and sidebar badge show — instead of counting historical marked-.duplicate rows. Extracted DuplicateDetector.reviewSnapshots(jobs:) (exclude .duplicate + require capture) and unresolvedPairCount; Sidebar.refreshDuplicateCount and DuplicatesView.refreshPairsInBackground now use reviewSnapshots so the rule is shared. Dashboard queries DuplicateDecision and recomputes when decisions change, so resolved-hash suppression matches the screen. Test (testUnresolvedPairCountSharedHelper) covers unresolved pair (=1), marked-duplicate exclusion (=0), and resolved-decision suppression (=0). Full CoreTests (925) green; lint clean.
<!-- SECTION:FINAL_SUMMARY:END -->
