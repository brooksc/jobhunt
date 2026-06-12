---
id: TASK-405
title: Add xcodebuild timeout guard to VM test script
status: To Do
assignee: []
created_date: '2026-06-12 23:54'
labels: []
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
If the app crashes at launch or xcodebuild hangs waiting for the test host, `run-ui-tests-in-vm.sh` waits indefinitely. Add a `timeout 900` wrapper around the xcodebuild call in `GUEST_TEST`. On timeout, print a clear TIMEOUT message and exit with code 124 so the cleanup trap shuts down the VM cleanly. Define the timeout value as a named constant at the top of the script.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 xcodebuild is wrapped with a 15-minute timeout in GUEST_TEST
- [ ] #2 A hung xcodebuild exits with a clear TIMEOUT message
- [ ] #3 The VM is stopped cleanly after a timeout
- [ ] #4 Timeout value is a named constant at the top of the script
<!-- AC:END -->
