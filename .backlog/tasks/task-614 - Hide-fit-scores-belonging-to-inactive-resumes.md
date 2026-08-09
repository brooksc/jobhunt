---
id: TASK-614
title: Hide fit scores belonging to inactive resumes
status: Done
assignee: []
created_date: '2026-07-22 18:46'
updated_date: '2026-08-09 19:27'
labels:
  - bug
  - resume
  - fit-scoring
  - workflow
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Services/ResumeService.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Jobs/JobsSortLogic.swift
  - app/Views/Dashboard/DashboardView.swift
  - app/Platform/PlatformIntegration.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When a resume is deactivated, retain its historical JobFitScore records but exclude them from all user-facing fit results. Current behavior still lists inactive-resume score cards in the Fit tab and computes the denormalized job headline from the best score across all resumes, allowing an old inactive resume to drive job rows, filters, sorting, dashboard recommendations, and detail summaries.

Define the visible/canonical fit result as the best completed score among active, resume-linked records only. Running, pending, and failed states from inactive resumes must likewise not drive the job-level fit state. Deactivating a resume should immediately hide its score everywhere without deleting it; reactivating it should make the preserved score eligible again without requiring a new scoring run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Fit tab lists score cards only for active resumes and computes its best-match hero and scored-resume count from active resumes only.
- [x] #2 The overview fit ring and scored-resume count exclude inactive-resume scores.
- [x] #3 Job list score display, fit sorting, minimum-fit filters, dashboard recommendations/aggregates, and other consumers of the job-level fit mirror cannot be driven by an inactive resume.
- [x] #4 The canonical job-level fit score/status/JSON is recomputed from active, resume-linked scores only, including pending, running, and failed states.
- [x] #5 If no active resume has an eligible score or in-flight state, the UI shows the existing fit-unavailable/not-scored state rather than a stale historical score.
- [x] #6 Deactivating a resume preserves its JobFitScore records but immediately removes their influence from visible scores and aggregates; reactivating it restores their eligibility without rescoring.
- [x] #7 With multiple active resumes, the highest completed active score remains the headline result and all active resume cards remain available for comparison.
- [x] #8 Prompt AI resume selection and any strong-match notification logic do not choose or advertise a score from an inactive resume.
- [x] #9 Focused tests cover deactivation, reactivation, all-resumes-inactive, mixed active/inactive scores, inactive pending/failed states, list filtering/sorting, dashboard recommendations, and Fit/Overview detail presentation.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Most of this was already in place — `computedFitMirror`, the Fit tab's `sortedScores`, and Prompt AI's résumé pick all filtered on `resume?.active`. Three real gaps remained.

**1. Deactivating didn't move the headline.** `ResumeService.setResumeActive` flipped the flag and stopped. `setActiveResume` and `deleteResume` both recompute the mirrors; the toggle didn't. So a shelved résumé's card vanished from the Fit tab while its score kept driving the job list, filters, sorting and the dashboard — the two views disagreed until something unrelated triggered a recompute. It now calls `recomputeAllJobFitMirrors()`.

**2. `.failed` ignored active.** In `computedFitMirror`, the succeeded / running / pending branches all required an active résumé; the `.failed` branch did not, so a failure belonging to a shelved résumé still set the job's fit state.

**3. The ready-notification advertised the wrong number.** `QueueActor` emitted `fitResult.overall` — the score just computed — so manually rescoring a shelved résumé announced a number the app shows nowhere. It now reads the job's active-only mirror via a new `BackgroundStore.jobMirrorScore(jobNumber:)`, falling back to the raw result if that read fails.

Criterion 3's other consumers needed no change: the job list, sorting, min-fit filter and dashboard all read the job-level mirror, which is now correct at the moment of the toggle.

**Tests** (`InactiveResumeFitMirrorTests`, 4): deactivating drops that résumé out of the headline (90 → 40); reactivating restores it with both `JobFitScore` rows intact and no rescoring; all-inactive leaves score `nil` and status `.none` rather than a stale number; and a failed score from an inactive résumé no longer sets the job's fit state.
<!-- SECTION:FINAL_SUMMARY:END -->
