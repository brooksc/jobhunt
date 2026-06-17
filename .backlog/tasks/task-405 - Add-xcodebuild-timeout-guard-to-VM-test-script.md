---
id: TASK-405
title: Add xcodebuild timeout guard to VM test script
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
If the app crashes at launch or xcodebuild hangs waiting for the test host, `run-ui-tests-in-vm.sh` waits indefinitely. Add a `timeout 900` wrapper around the xcodebuild call in `GUEST_TEST`. On timeout, print a clear TIMEOUT message and exit with code 124 so the cleanup trap shuts down the VM cleanly. Define the timeout value as a named constant at the top of the script.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 xcodebuild is wrapped with a 15-minute timeout in GUEST_TEST
- [x] #2 A hung xcodebuild exits with a clear TIMEOUT message
- [x] #3 The VM is stopped cleanly after a timeout
- [x] #4 Timeout value is a named constant at the top of the script
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Wrapped both in-VM xcodebuild invocations (host-built and build-in-VM paths) in GUEST_TEST with a `$TIMEOUT_CMD` that resolves to `timeout 900`/`gtimeout 900` in the guest (AC#1; macOS has no `timeout` by default, so coreutils `gtimeout` is the fallback, with a warning if neither exists). On timeout the guest captures exit 124 and prints "✗ TIMEOUT: xcodebuild exceeded 900s and was killed (exit 124)" (AC#2); the host's `set -euo pipefail` + `trap cleanup EXIT` then stop the VM cleanly (AC#3). The timeout is a named constant `XCODEBUILD_TIMEOUT=900` at the top of the script (AC#4). `bash -n` clean; documented in docs/vm-testing.md. Can't run the VM here — verified by syntax + review; note the guest needs `timeout`/`gtimeout` present for the cap to apply (warned otherwise).
<!-- SECTION:FINAL_SUMMARY:END -->
