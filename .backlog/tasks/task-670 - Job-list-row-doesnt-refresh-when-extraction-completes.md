---
id: TASK-670
title: Job list row rendered clipped until the list was rebuilt
status: Done
assignee: []
created_date: '2026-08-07 21:10'
updated_date: '2026-08-07 21:53'
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
- [x] #1 A newly captured job's list row shows company, location and salary as soon as extraction succeeds, with no list rebuild
- [x] #2 The list row and the detail pane never disagree about the same job's extracted fields
- [ ] #3 Covered by a test that asserts the row's projection updates when the underlying Job's extracted fields change
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed in `dbdebd7d`. **The premise of this task was wrong** — it was filed as a data-refresh bug and it is a layout bug.

## What it actually was

`List` caches a row's height when the row is created. A job is inserted at capture time with one line — just its title — and measured at 24pt. Extraction then adds company, location and salary and swaps the placeholder for a 36pt fit ring, but the cached 24pt stands, so the ring and the whole second line render clipped. Rebuilding the list re-measures the row, which is why changing the sort "fixed" it and why it looked like stale data.

## How the misdiagnosis was caught

Two measurements, both cheap:

1. An MCP `update_job` against a visible row updated it **instantly** — so `@Query` propagation from the background `@ModelActor` works fine, and the data theory was dead.
2. Accessibility geometry: `row1` height **24pt**, `row2` height **50pt**, while row 1's company/location/salary were present in the accessibility tree the entire time. Text present, row too short to draw it.

## The fix, and two that don't work

Re-identify the row on `extractionStatus` (`.id("\(job.id)#\(job.extractionStatus.rawValue)")`) so `List` invalidates exactly the one row that needs re-measuring. Verified on a real capture: row1 24pt → 50pt, other rows unchanged at 50pt.

Nothing **inside** the row works, and both were tried:

- `.frame(minHeight: 36)` and `.frame(height: 36)` — clipped by the cached height; row stayed at 24pt.
- `.frame(minHeight: 44)` — did clear the clipping, but only by re-measuring *every* row, making the whole list 8pt taller (50 → 58). That was luck, not a fix.

## Not done

Acceptance criterion 3 (a regression test) is **not** met. `JobsView` lives in the app target, which has no unit-test target, and row height is a SwiftUI layout property that a unit test wouldn't observe anyway. The verification was manual, via accessibility geometry during a live capture. Same coverage gap as `JobsSortLogic` — worth fixing once by compiling those files into CoreTests the way the migrator sources are.
<!-- SECTION:FINAL_SUMMARY:END -->
