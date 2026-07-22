---
id: TASK-614
title: Hide fit scores belonging to inactive resumes
status: To Do
assignee: []
created_date: '2026-07-22 18:46'
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
- [ ] #1 The Fit tab lists score cards only for active resumes and computes its best-match hero and scored-resume count from active resumes only.
- [ ] #2 The overview fit ring and scored-resume count exclude inactive-resume scores.
- [ ] #3 Job list score display, fit sorting, minimum-fit filters, dashboard recommendations/aggregates, and other consumers of the job-level fit mirror cannot be driven by an inactive resume.
- [ ] #4 The canonical job-level fit score/status/JSON is recomputed from active, resume-linked scores only, including pending, running, and failed states.
- [ ] #5 If no active resume has an eligible score or in-flight state, the UI shows the existing fit-unavailable/not-scored state rather than a stale historical score.
- [ ] #6 Deactivating a resume preserves its JobFitScore records but immediately removes their influence from visible scores and aggregates; reactivating it restores their eligibility without rescoring.
- [ ] #7 With multiple active resumes, the highest completed active score remains the headline result and all active resume cards remain available for comparison.
- [ ] #8 Prompt AI resume selection and any strong-match notification logic do not choose or advertise a score from an inactive resume.
- [ ] #9 Focused tests cover deactivation, reactivation, all-resumes-inactive, mixed active/inactive scores, inactive pending/failed states, list filtering/sorting, dashboard recommendations, and Fit/Overview detail presentation.
<!-- AC:END -->
