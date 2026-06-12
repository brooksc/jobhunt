---
id: TASK-404
title: Add --class and --test flags to run-ui-tests-in-vm.sh
status: To Do
assignee: []
created_date: '2026-06-12 23:54'
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
- [ ] #1 --class <Name> runs only AppUITests/<Name> in the VM
- [ ] #2 --test <Name/method> runs only that single test method
- [ ] #3 docs/vm-testing.md debugging section shows the new flags
<!-- AC:END -->
