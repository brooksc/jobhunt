---
id: TASK-660
title: >-
  Fit score ring doesn't refresh after a correction — requirement moves but the
  number is stale until reselect
status: To Do
assignee: []
created_date: '2026-08-04 04:23'
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
- [ ] #1 Saving a correction updates the score ring and the per-resume score in place, with no reselect
- [ ] #2 A row forced to met does not display evidence text written for the opposite verdict
- [ ] #3 Test: applying feedback to a scored job updates the projection's overall score, not only its requirement rows
- [ ] #4 scripts/demo/drive.sh scene 06 can be simplified to drop the reselect once this is fixed
<!-- AC:END -->
