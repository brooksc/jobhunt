---
id: TASK-605
title: Investigate missed duplicate match between jobs 163 and 193
status: Done
assignee: []
created_date: '2026-07-21 21:47'
updated_date: '2026-07-22 18:20'
labels:
  - bug
  - duplicates
  - workflow
dependencies: []
references:
  - core/Services/DuplicateDetector.swift
  - core/Services/BackgroundStore.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Duplicates/DuplicatesView.swift
  - tests/CoreTests/DuplicateDetectorTests.swift
  - tests/CoreTests/BackgroundStoreTests.swift
priority: medium
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jobs 163 and 193 appear to represent the same job, but the manual and/or automatic duplicate scan does not identify them as a duplicate pair. Reproduce detection using their persisted capture and extracted fields, record which eligibility gate or matching signal rejects the pair, and correct the false negative without materially increasing unrelated duplicate suggestions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The duplicate scan result for jobs 163 and 193 is reproduced using their persisted status, extraction state, URLs, titles, companies, locations, descriptions, hashes, and prior DuplicateDecision records.
- [ ] #2 The exact eligibility filter, normalization difference, evidence threshold, resolved-pair suppression, or persistence issue preventing the match is documented.
- [ ] #3 After the fix, scanning while both records remain eligible identifies jobs 163 and 193 as a reviewable duplicate pair with an understandable reason and confidence.
- [ ] #4 A sanitized regression fixture matching jobs 163 and 193 covers both batch/manual scanning and incremental detection where applicable.
- [ ] #5 Existing tests for true duplicates, non-duplicates, resolved pairs, terminal statuses, and already-marked duplicates remain passing.
<!-- AC:END -->
