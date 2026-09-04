---
id: TASK-717
title: >-
  run-ui-tests-in-vm.sh runs the previously built bundle when the host build
  fails
status: To Do
assignee: []
created_date: '2026-09-04 18:47'
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
- [ ] #1 A failing host build causes the script to exit non-zero without running any tests
- [ ] #2 The failure message names the build error rather than reporting test results
- [ ] #3 Verified by deliberately breaking a source file and confirming the script stops
<!-- AC:END -->
