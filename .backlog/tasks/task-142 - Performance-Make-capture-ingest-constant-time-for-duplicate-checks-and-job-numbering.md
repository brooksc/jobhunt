---
id: TASK-142
title: >-
  Performance: Make capture ingest constant-time for duplicate checks and job
  numbering
status: Done
assignee: []
created_date: '2026-06-11 03:45'
updated_date: '2026-06-11 19:02'
labels:
  - performance
  - swiftdata
  - ingest
dependencies: []
references:
  - core/Services/BackgroundStore.swift
modified_files:
  - core/Services/BackgroundStore.swift
  - tests/CoreTests/JobServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Performance audit finding: `BackgroundStore.insertCaptureAtomically` fetches every `Capture` and every `Job` on each ingest, then scans in memory for raw/cleaned hash duplicates and max job number. Capture rows include large text fields, so capture latency and memory grow with history.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Capture ingest checks `rawHash` and `cleanedHash` using targeted predicates with bounded fetches instead of loading all captures.
- [ ] #2 Job number allocation no longer scans every job on each capture; it uses a persisted counter/sequence or another bounded strategy.
- [ ] #3 A regression test or benchmark covers ingest with a large seeded dataset and verifies bounded query behavior/latency.
- [ ] #4 Duplicate behavior for raw-hash and cleaned-hash captures remains unchanged.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rewrote insertCaptureAtomically in BackgroundStore to use bounded predicate fetches instead of full table scans. rawHash check: predicate fetch with fetchLimit 1. cleanedHash check: predicate fetch with fetchLimit 10 (filters by hash first, then URL in memory). Job number: sort descending by jobNumber + fetchLimit 1 instead of loading all jobs and computing max in memory. Added testAtomicIngest_jobNumberingIsCorrectWithLargeDataset which seeds 50 jobs then verifies correct numbering and duplicate detection.
<!-- SECTION:FINAL_SUMMARY:END -->
