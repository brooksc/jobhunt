---
id: TASK-306
title: 'Persistence: Recompute job fit mirrors when active resume changes'
status: To Do
assignee: []
created_date: '2026-06-12 19:34'
labels:
  - audit
  - persistence
  - fit-scoring
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Services/ResumeService.swift
  - app/Views/Jobs/JobsView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Job.fitScore, fitStatus, and fitScoreJSON are documented as denormalized fields for the active resume's score, but ResumeService.setActiveResume only flips active flags. Existing jobs can keep the previous active resume's score, making lists, dashboard metrics, saved searches, and exports stale.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Changing the active resume recomputes every affected Job.fitScore, fitStatus, and fitScoreJSON from the new active resume's JobFitScore records.
- [ ] #2 Jobs without a score for the new active resume are reset to fitStatus .none and nil score/json.
- [ ] #3 Regression tests cover switching active resumes with different per-job scores.
<!-- AC:END -->
