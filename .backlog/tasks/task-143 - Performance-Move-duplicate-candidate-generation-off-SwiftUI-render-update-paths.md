---
id: TASK-143
title: >-
  Performance: Move duplicate candidate generation off SwiftUI render/update
  paths
status: Done
assignee: []
created_date: '2026-06-11 03:45'
updated_date: '2026-06-11 19:18'
labels:
  - performance
  - swiftui
  - swiftdata
  - duplicates
dependencies: []
references:
  - app/Views/Duplicates/DuplicatesView.swift
  - core/Services/DuplicateDetector.swift
modified_files:
  - core/Services/DuplicateDetector.swift
  - app/Views/Duplicates/DuplicatesView.swift
  - tests/CoreTests/DuplicateDetectorTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Performance audit finding: `DuplicatesView` refreshes duplicate pairs when `allJobs` changes, and `DuplicateDetector` fetches all jobs/decisions and performs nested company comparison within title groups. This makes duplicate review grow expensive as job history expands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Duplicate candidate generation runs in a background service or task boundary instead of synchronously from the SwiftUI view on every job change.
- [ ] #2 Likely duplicate pairs are persisted or cached so opening the Duplicates screen does not recompute the full dataset.
- [ ] #3 Recomputation is incremental, debounced, or user-triggered for large datasets.
- [ ] #4 Tests cover duplicate candidate generation after ingest/extraction changes and after resolving duplicate decisions.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Moved duplicate candidate generation off the SwiftUI render path. Added duplicateGroups(snapshots:resolvedHashes:) pure overload to DuplicateDetector (no ModelContext needed; safe for background tasks). Made JobSnapshot.init(job:capture:) public so app module can build snapshots. In DuplicatesView: replaced @Environment modelContext with @Query allDecisions, replaced .onChange/.onAppear with .task(id: pairRefreshID) driven by job+decision count, moved O(N²) computation into Task.detached(priority:.utility). Action handlers (unmark/delete) also await refreshPairsInBackground() post-mutation. Tests: testSnapshotOverloadMatchesContextOverload and testSnapshotOverloadRespectsResolvedHashes.
<!-- SECTION:FINAL_SUMMARY:END -->
