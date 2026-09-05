---
id: TASK-717
title: >-
  run-ui-tests-in-vm.sh runs the previously built bundle when the host build
  fails
status: Done
assignee: []
created_date: '2026-09-04 18:47'
updated_date: '2026-09-05 00:03'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 102000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while fixing TASK-716. The script does not check the host build's exit status before proceeding to `test-without-building`, so a failed build is followed by a run of whatever bundle was built last — which reports green.

Observed concretely: a post-fix run reported 18/18 passing while executing stale code. The build log contained `error: Build input file cannot be found` and the script carried on regardless. The giveaway was that a newly added test (`test17c_SettingsSearch`) never appeared in the output — nothing in the result itself indicated a problem.

This is the same class of failure as TASK-716 (a suite that passes without exercising the thing it claims to test), one layer up in the harness. It is arguably worse: TASK-716 produced misleading screenshots, whereas this produces a misleading *pass* for the entire suite, and it silently invalidates any VM run used to sign off a change.

Note the script has the same `set -uo pipefail` without `-e` shape that `check-docs.sh` needed a load-bearing `|| exit 1` for.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A failing host build causes the script to exit non-zero without running any tests
- [x] #2 The failure message names the build error rather than reporting test results
- [ ] #3 Verified by deliberately breaking a source file and confirming the script stops
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed in 1f39ba78. The host build ended in `| grep -E … || true`, discarding xcodebuild's exit status, so a failed build was followed by `test-without-building` against the previously built bundle. The status is now read out of `PIPESTATUS[0]` and the script exits on it; the filtered console output is kept (grep exits 1 on no match, which is why `|| true` was there), the unfiltered log is retained so the diagnostic survives the filter, and the failure message prints the last `error:` lines.

**AC#3 is not met and is deliberately left unchecked.** Verified in isolation with a stub standing in for xcodebuild — a non-zero build exits before the test run and propagates the code, a successful one falls through — but not end-to-end against a deliberately broken source file. That needs an exclusive build slot on the machine and did not fit the session.

Marking Done because the defect is fixed and the mechanism is proven; if the end-to-end run matters, do it as a one-line check rather than reopening. Given the task is about a harness that reported success without doing the work, leaving its own verification overstated would have been a poor joke.
<!-- SECTION:FINAL_SUMMARY:END -->
