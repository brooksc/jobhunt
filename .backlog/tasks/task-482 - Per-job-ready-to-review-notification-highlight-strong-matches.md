---
id: TASK-482
title: Per-job "ready to review" notification (highlight strong matches)
status: To Do
assignee: []
created_date: '2026-06-18 02:45'
labels:
  - notifications
  - ux
  - workflow
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Today `PlatformIntegration.handleJobReady` only posts an individual macOS notification for a strong match (fit ≥ 75% → "Strong Match!"). A single job that scores below 75% gets NO notification (it's suppressed via `processingBatchCount`; only a batch of >1 processed jobs, or any failures, fires a "N jobs processed" summary at `.processingComplete`).

Desired (per the workflow in docs/workflow.md): notify once per completed job that it's ready to review, regardless of fit score, while still highlighting strong matches specially. Preserve bulk-batching so a large re-extraction run (e.g. 50 jobs) doesn't fire 50 individual notifications — single/few jobs notify individually, large batches summarize.

References: app/Platform/PlatformIntegration.swift (handleJobReady / handleEvent / processingBatchCount), docs/workflow.md (step 4).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A single job completing extraction+fit posts one 'ready to review' notification regardless of fit score
- [ ] #2 Strong matches (fit ≥ 75%) are still visually distinguished (e.g. 'Strong Match!' title)
- [ ] #3 A bulk run (N jobs above a small threshold) still summarizes instead of firing N individual notifications
- [ ] #4 Clicking the notification deep-links to the job (existing jobNumber userInfo path)
- [ ] #5 Jobs with no fit score (no active resume) still notify as 'ready to review' without a fit figure
<!-- AC:END -->
