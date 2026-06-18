---
id: TASK-482
title: Per-job "ready to review" notification (highlight strong matches)
status: Done
assignee: []
created_date: '2026-06-18 02:45'
updated_date: '2026-06-18 03:15'
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
- [x] #1 A single job completing extraction+fit posts one 'ready to review' notification regardless of fit score
- [x] #2 Strong matches (fit ≥ 75%) are still visually distinguished (e.g. 'Strong Match!' title)
- [x] #3 A bulk run (N jobs above a small threshold) still summarizes instead of firing N individual notifications
- [x] #4 Clicking the notification deep-links to the job (existing jobNumber userInfo path)
- [x] #5 Jobs with no fit score (no active resume) still notify as 'ready to review' without a fit figure
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`PlatformIntegration` now gives a per-job "ready to review" notification, replacing the old strong-match-only-or-silent behavior.

Because `jobReady` fires twice per job (after extraction with a nil fit, then after fit with the score), the handler accumulates ready jobs in `pendingReady` keyed by job number (a non-nil score wins the de-dup) and decides at `.processingComplete`:
- **≤ 3 ready jobs in the drain:** one notification per job — "Strong Match!" for fit ≥ 75% (AC#2), "Ready to Review" otherwise (AC#1). Jobs with no fit score (no active resume) notify with just the title (AC#5). Clicking deep-links to the job via the existing `jobNumber` userInfo (AC#4).
- **> 3:** a single summary ("N jobs ready to review · K strong matches"), so a bulk re-extraction doesn't fire one banner per job (AC#3).

Failures in the drain still surface (folded into the per-job path or the summary). The old `processingBatchCount` field and `handleJobReady` were removed.

Verified: app builds (Jobhunt-DMG) and the full fast gate is green. Note: `PlatformIntegration` is @MainActor notification glue with no existing unit-test harness, so this is build-verified rather than unit-tested (the testable queue-side behavior is covered under TASK-483).
<!-- SECTION:FINAL_SUMMARY:END -->
