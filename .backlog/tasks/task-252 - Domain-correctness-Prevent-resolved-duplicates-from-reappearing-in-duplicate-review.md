---
id: TASK-252
title: >-
  Domain correctness: Prevent resolved duplicates from reappearing in duplicate
  review
status: Done
assignee: []
created_date: '2026-06-12 02:41'
updated_date: '2026-06-12 03:09'
labels:
  - audit
  - domain
  - duplicates
dependencies: []
references:
  - core/Services/DuplicateDetector.swift
  - app/Views/Duplicates/DuplicatesView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`DuplicateDetector.detectDomainDuplicates` filters out passed, archived, and closed jobs, but it explicitly allows candidates with status `duplicate`. It also does not exclude jobs already linked via `duplicateOfJobID`, so already-marked duplicates can continue surfacing in review unless a separate `DuplicateDecision` happens to suppress them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Duplicate detection excludes already-resolved duplicate jobs unless the UI intentionally requests a resolved-duplicates audit mode.
- [ ] #2 Duplicate decisions and `duplicateOfJobID` semantics are documented together.
- [ ] #3 Tests cover already-marked duplicates not reappearing in the active duplicate-review queue.
<!-- AC:END -->
