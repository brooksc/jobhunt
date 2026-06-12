---
id: TASK-307
title: 'Persistence: Clear or recompute job fit mirrors when deleting active resume'
status: Done
assignee: []
created_date: '2026-06-12 19:34'
updated_date: '2026-06-12 19:50'
labels:
  - audit
  - persistence
  - fit-scoring
dependencies: []
references:
  - core/Services/ResumeService.swift
  - core/Models/Resume.swift
  - core/Services/BackgroundStore.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Deleting an active resume cascades its JobFitScore rows and may promote another resume, but affected Job.fitScore fields are not recomputed. Jobs can retain a score whose backing JobFitScore was deleted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Deleting an active resume recomputes job-level fit mirrors from the promoted active resume, or clears them if no active scored resume remains.
- [ ] #2 Deleting an inactive resume does not alter unrelated active-resume job mirrors.
- [ ] #3 Regression tests cover active resume deletion, promotion, and no-remaining-resume cases.
<!-- AC:END -->
