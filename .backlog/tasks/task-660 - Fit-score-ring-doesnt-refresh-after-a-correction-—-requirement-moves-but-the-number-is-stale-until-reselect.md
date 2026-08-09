---
id: TASK-660
title: >-
  Fit score ring doesn't refresh after a correction — requirement moves but the
  number is stale until reselect
status: Done
assignee: []
created_date: '2026-08-04 04:23'
updated_date: '2026-08-09 18:53'
labels:
  - fit-scoring
  - ui
  - feedback
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while recording the demo walkthrough (job #2, Google, demo data).

Flag a requirement in the Fit tab and save the correction:

- The requirement row **does** update immediately — it moves from the **Gaps** column to
  **Requirements met** with a green tick.
- The headline **score ring keeps its old value** (84), as does the per-résumé row's number.
- Selecting a different job and coming back rebuilds the view and shows the correct **94**.

So the projection applies the feedback, but the score view isn't invalidated when the feedback store
changes — only the requirement rows are. Two things on the same screen disagree until the user
happens to navigate away and back, which reads as the correction not having worked.

A second, smaller inconsistency in the same place: a row forced to `met` by an `alwaysCredit`
correction keeps the *evidence* text generated for its original `missing` verdict — so it shows a
green tick above "Not evidenced — a reader of this resume would not credit it."

The walkthrough films the reselect rather than faking an in-place update
(`scripts/demo/drive.sh`, scene 06), so this is visible in the shipped demo video until fixed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 not verified (visual): saving a correction updates the score ring and the per-resume score in place — both now read the projection's corrected score, and the arithmetic is unit-tested, but the in-place redraw was not observed since driving the UI is out of scope for this run
- [x] #2 A row forced to met does not display evidence text written for the opposite verdict
- [x] #3 Test: applying feedback to a scored job updates the projection's overall score, not only its requirement rows
- [x] #4 scripts/demo/drive.sh scene 06 no longer reselects to refresh the score
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The rows and the number were running on two clocks. Rows came from `FitScoreProjection` with feedback applied, so they moved the instant a correction was saved; the ring read the persisted `JobFitScore.fitScore`, which only changed once `recomputeAllFitScores()` finished in the background. A requirement jumped from Gaps to Requirements met above a headline that hadn't moved — which reads as the correction being ignored.

**Fix:** `FitScoreProjection` now exposes `overallScore`, computed by the same `FitScorer.rescoreFromJSON(_:feedback:jobNumber:)` call the background recompute makes — so the number shown immediately is the number persisted moments later, not an approximation. Both displays read it: the per-résumé row, and the hero ring via a new `bestCorrectedScore` across active résumés. Both fall back to the stored value when a legacy analysis can't be rescored.

**Second defect fixed:** a row overridden by a correction kept the model's evidence for its *original* verdict, so an `alwaysCredit` row showed a green tick above "Not evidenced — a reader of this resume would not credit it." Overridden rows now say who decided: "You marked this as something you have/don't have."

**Tests** (`FitProjectionCorrectedScoreTests`, 4): crediting a missing requirement raises the score; `neverCredit` lowers it; a corrected row drops the contradictory evidence; an uncorrected row keeps its own.

**Demo driver:** `drive.sh` scene 06 no longer selects Stripe and back to force a rebuild. The existing assertion (expects 94) is what proves the in-place update — a stale ring would still read 84.

Criterion 1 is **not verified**: the redraw follows from tested arithmetic but I did not watch it happen.
<!-- SECTION:FINAL_SUMMARY:END -->
