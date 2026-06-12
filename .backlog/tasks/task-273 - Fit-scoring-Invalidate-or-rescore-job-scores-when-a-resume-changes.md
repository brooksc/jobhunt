---
id: TASK-273
title: 'Fit scoring: Invalidate or rescore job scores when a resume changes'
status: Done
assignee: []
created_date: '2026-06-12 03:33'
updated_date: '2026-06-12 03:38'
labels:
  - audit
  - resume
  - fit-scoring
  - data-consistency
dependencies: []
references:
  - core/Services/ResumeService.swift
  - core/Models/JobFitScore.swift
  - app/Views/Detail/JobDetailView.swift
modified_files:
  - core/Services/BackgroundStore.swift
  - core/Services/ResumeService.swift
  - tests/CoreTests/ResumeServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Resume updates change the text used for fit scoring, but existing JobFitScore records remain visible as if current. Add an invalidation, stale marker, or automatic rescore path when resume text changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Updating a resume marks related fit scores stale, deletes them, or queues rescoring according to an explicit product decision.
- [x] #2 Job detail UI distinguishes stale scores from current scores if stale records are retained.
- [x] #3 Tests cover editing a resume after scoring at least one job.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Decision: delete fit scores on text change (no stale markers retained, so AC2 is satisfied by absence). Added `BackgroundStore.deleteFitScores(forResumeID:)` which deletes all `JobFitScore` records for the resume and resets denormalized `Job.fitScore`/`fitStatus`/`fitScoreJSON` on affected jobs (or promotes the best remaining score if other resumes were also scored). `ResumeService.updateResume` now detects text changes and calls `deleteFitScores` only when text actually changed (name-only updates are unaffected). Two new tests: `testUpdateResumeText_deletesFitScores` and `testUpdateResumeNameOnly_doesNotDeleteFitScores`. All CoreTests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
