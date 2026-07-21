---
id: TASK-611
title: >-
  perf: cache JobDetailProjection / FitScoreProjection in detail views
  (re-parsed 3–4× per render)
status: To Do
assignee: []
created_date: '2026-07-21 23:46'
labels:
  - performance
  - tech-debt
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two detail views recreate a projection (which runs JSONSerialization on stored blobs) multiple times per render:

- `OverviewTabView` (`JobDetailView.swift:588`): `projection` / `summary` / `requirements` / `niceToHaves` each construct a fresh `JobDetailProjection(job:)`, which parses `job.extractedJSON` AND `job.manualOverridesJSON` (`Projections.swift:15,24`) — 3 full parses of both blobs per body render, and body re-renders per keystroke while inline-editing a field.
- `ResumeScoreCard` (`JobDetailView.swift:1276`): `fitProjection` / requirementsMet / requirementsNotMet / requirementAssessments / dimensions each construct `FitScoreProjection(fitScore:)`, which parses `fitScoreJSON` (`Projections.swift:79`) — up to 4 parses per render, multiple cards in the Fit tab.

Fix: compute each projection once — either a single `let` threaded through body, or cache in @State recomputed via `.onChange(of: job.extractedJSON/manualOverridesJSON)` (Overview) and `.onChange(of: fitScore.fitScoreJSON)` (ResumeScoreCard). Care needed: the cache must invalidate when an inline edit commits (Overview) or a re-score lands (ResumeScoreCard), so it isn't stale — that invalidation is why this is a careful refactor rather than a one-liner. DashboardView's `.onChange`-cached `derived` is the pattern to follow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Overview/ResumeScoreCard parse each JSON blob at most once per underlying-data change, not 3–4× per render
- [ ] #2 Projections still update immediately after an inline edit commits / a re-score completes (no stale display)
<!-- AC:END -->
