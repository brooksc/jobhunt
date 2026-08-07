---
id: TASK-670
title: Job list row doesn't refresh when extraction completes
status: To Do
assignee: []
created_date: '2026-08-07 21:10'
labels:
  - bug
  - ui
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A newly captured job's row in the Jobs list keeps rendering as a bare single line — title plus its status badge, with **no company, location or salary** — after extraction has already succeeded. The detail pane beside it shows all three fields at the same moment.

The row fills in only once the list is **rebuilt**. In the demo recording that happens when the sort key changes; at that point the same row renders correctly as two lines: `Principal Technical Program Manager, Developer Productivity / Reddit · Remote - United States · Remote · $260k–365k`.

## Evidence

Caught in the walkthrough recording (`/tmp/master5.mov`, scenes at `/tmp/scenes5.txt`), where it persists for roughly 20 seconds:

- extraction completes ~t=95s (scene `05-filled-in`)
- detail pane shows company, location, salary and a fit score immediately
- the list row stays single-line from t=95 through t=110
- the sort switches to Fit Score at t=110 (scene `07-sort`) and the row renders in full

## Why it matters beyond the demo

This is the first thing a user sees after their very first capture. The row looks like the capture half-failed, at exactly the moment the app is trying to demonstrate that it worked. It also makes the list disagree with the detail pane about the same job, which is the class of inconsistency this codebase has already been bitten by (the score/rows disagreement that motivated applying `ScoringFeedback` in both places).

## Where to look

The denormalised fields on `Job` (`company`, `location`, `salaryMin`/`salaryMax`, `remoteType`) are populated by the extraction write path. The detail pane sees the update and the list does not, so the suspect is the list's observation of those fields rather than the write itself — a `@Query`/snapshot in `JobsView` not re-evaluating, rather than missing data. Confirm by checking whether the row corrects itself on any list rebuild (changing sort, changing filter, switching sidebar section and back) but not on its own.

## Notes

- Do NOT reach for a scroll or layout fix. The row is not clipped and the list is not mis-scrolled — that was the initial misdiagnosis, and a scroll-to-top "fix" was written and then reverted.
- Reproduce with `./scripts/demo/reset.sh` + a real capture; the demo seed alone won't show it, because seeded rows are written already-populated.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A newly captured job's list row shows company, location and salary as soon as extraction succeeds, with no list rebuild
- [ ] #2 The list row and the detail pane never disagree about the same job's extracted fields
- [ ] #3 Covered by a test that asserts the row's projection updates when the underlying Job's extracted fields change
<!-- AC:END -->
