---
id: TASK-039
title: 'FitScorer: weighted 5-dimension scoring + penalty model + rescore'
status: In Progress
assignee:
  - claude
created_date: '2026-06-07 22:45'
updated_date: '2026-06-08 02:05'
labels:
  - swift-rewrite
  - core
  - llm
milestone: m-1
dependencies:
  - TASK-034
documentation:
  - swift-plan.md
  - server/extract.js
  - server/rescore.js
priority: high
ordinal: 1600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port resume-fit scoring math and the no-LLM rescore path. (The LLM call that produces dimension scores lives in the ExtractionEngine task; THIS task owns the deterministic scoring/weighting/penalty math and recompute.)

## Read first
- swift-plan.md §8.5 (fit scoring weights + penalty), §9 (rescore as pure recompute), §10.2 #3 (Fit score tab: dimensions breakdown, requirements met/not met).
- Legacy server/extract.js — the fit-score weighting (required 45%, preferred 5%, skills 15%, experience 20%, domain 15%), penalty model (−5/missing requirement, −10/domain-gap keyword e.g. ASIC/FPGA/RTL/hyperscaler, cap −50), final = max(0, weighted−penalty).
- Legacy server/rescore.js — recompute fit_score/fit_score_json from current weights with no LLM calls.

## Implement (core/Services/FitScorer.swift)
- `FitScorer.computeScore(dimensions:requirements:)` → overall 0–100 + per-dimension breakdown + applied penalty, producing the fitScoreJSON structure the Detail UI reads.
- `rescoreAll(store:)` recompute over all scored jobs/JobFitScore rows using current weights/penalty (port rescore.js); update Job.fitScore for the active resume(s).
- Domain-gap keyword list as configurable constants matching legacy.

## Dependencies
Depends on task-034 (Job/JobFitScore/Resume models). The ExtractionEngine (later task) calls this to turn LLM dimension output into stored scores.

## Tests (CoreTests)
- Weighted score + penalty on fixtures matches extract.js outputs; cap at −50; max(0,...) floor; rescore recompute matches rescore.js on a seeded store.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Weighted 5-dimension score + penalty reproduces extract.js results on fixtures (incl. cap and floor)
- [ ] #2 fitScoreJSON structure matches what the Detail Fit tab expects
- [ ] #3 rescoreAll recompute matches rescore.js on a seeded store and updates Job.fitScore
- [ ] #4 CoreTests cover weighting, penalty cap, floor, and rescore
<!-- AC:END -->
