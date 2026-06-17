---
id: TASK-404
title: Add --class and --test flags to run-ui-tests-in-vm.sh
status: Done
assignee: []
created_date: '2026-06-12 23:54'
updated_date: '2026-06-17 04:56'
labels: []
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When iterating on a failing test, running the full AppUITests suite (~8 min) is wasteful. Add convenience flags:

- `--class BehaviorUITests` → expands to `--only-testing AppUITests/BehaviorUITests`
- `--test BehaviorUITests/testSidebarNavigationChangesSections` → runs a single method

Update usage line in script header and add examples to the Debugging section of `docs/vm-testing.md`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 --class <Name> runs only AppUITests/<Name> in the VM
- [x] #2 --test <Name/method> runs only that single test method
- [x] #3 docs/vm-testing.md debugging section shows the new flags
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `--class <Class>` (→ `-only-testing AppUITests/<Class>`, AC#1) and `--test <Class/method>` (→ single method, AC#2) shortcuts to run-ui-tests-in-vm.sh's arg parser, plus the usage header. docs/vm-testing.md's "Isolate the failing suite" debugging section shows both shortcuts (AC#3). `bash -n` clean. Can't run the VM here — verified by syntax + review.
<!-- SECTION:FINAL_SUMMARY:END -->
