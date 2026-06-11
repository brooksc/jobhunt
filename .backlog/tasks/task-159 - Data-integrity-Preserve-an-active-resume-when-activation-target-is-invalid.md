---
id: TASK-159
title: 'Data integrity: Preserve an active resume when activation target is invalid'
status: To Do
assignee: []
created_date: '2026-06-11 20:56'
labels:
  - audit
  - data-integrity
  - resume
dependencies: []
references:
  - core/Services/ResumeService.swift
  - tests/CoreTests/ResumeServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ResumeService.setActiveResume(id:)` deactivates every resume before verifying that the requested resume exists. If the ID is stale or wrong, the app can end up with zero active resumes. Fetch and validate the target first, then update activation state atomically, and add regression coverage for invalid IDs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Calling `setActiveResume` with a missing ID leaves the previous active resume unchanged.
- [ ] #2 The service throws or otherwise reports a not-found result for invalid activation targets.
- [ ] #3 Tests cover valid activation, invalid activation, and the invariant that at most one resume is active.
<!-- AC:END -->
