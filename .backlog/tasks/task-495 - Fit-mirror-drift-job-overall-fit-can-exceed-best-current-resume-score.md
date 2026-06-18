---
id: TASK-495
title: 'Fit-mirror drift: job overall fit can exceed best current resume score'
status: Done
assignee: []
created_date: '2026-06-18 20:42'
labels:
  - bug
  - fit-scoring
  - data-integrity
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The job-level denormalized fit mirror (shown as "overall fit" on the Overview and the list badge) could show a higher number than the best individual resume in the Fit tab (e.g. 97 overall vs a 92 best match), and only appeared after navigating away and back.

Root cause: BackgroundStore.markFitScoreRunning set the JobFitScore record's status to .running but left its prior fitScore in place; computedFitMirror takes the MAX over records with a non-nil fitScore, so a resume that previously scored high kept driving the mirror while it was being re-scored. If the new score landed lower (or the re-score lagged), the headline stayed at the stale high value.

Fix: markFitScoreRunning clears the record's fitScore and recomputes the job mirror when re-scoring starts, so the mirror reflects only settled scores and converges to the new best.

Files: core/Services/BackgroundStore.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When a resume is re-scored, its prior score no longer drives the job mirror while in flight
- [ ] #2 After a re-score, the job overall fit equals the best current resume score (no stale higher value)
- [ ] #3 Regression test covers the clear-on-running + recompute behavior
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
markFitScoreRunning now clears the record's fitScore and calls recomputeJobFitSummary, so a resume being re-scored stops contributing its stale prior value to the job's fit mirror. The headline overall-fit now tracks the best settled resume score and converges to the new best when the re-score completes. Regression test (testMarkFitScoreRunning_clearsStaleScore_andRecomputesMirror): seed two resumes 97/80 → mirror 97; mark the 97 resume running → mirror drops to 80; save its new 92 → mirror 92 (never stuck at 97). Full fast gate green.

Note: existing stored jobs that already drifted will self-correct on the next re-score; a one-shot JobhuntMigrator --recompute-fit-mirrors (recomputeAllJobFitMirrors) also fixes historical drift out-of-band.
<!-- SECTION:FINAL_SUMMARY:END -->
