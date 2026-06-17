---
id: TASK-402
title: Auto-retrieve screenshots and xcresult from VM after test run
status: Done
assignee: []
created_date: '2026-06-12 23:53'
updated_date: '2026-06-17 05:12'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After the xcodebuild step completes in the Tart VM, `run-ui-tests-in-vm.sh` has no mechanism to copy artifacts back to the host. Screenshots written to `/tmp/jobhunt-screenshots/<timestamp>/` and the xcresult bundle in `DerivedData` are lost when the VM shuts down.

Add an artifact-retrieval phase to the script:
1. `scp -r` the screenshot directory to `./local-screenshots/<timestamp>/` on the host (only if it exists).
2. `scp -r` the xcresult bundle to `./build/UITestResults.xcresult` on the host (overwriting, so the latest run is always at that path).
3. Print the host paths at the end of the run so the developer knows where to look.
4. Retrieval should run even when tests fail (retrieve before the cleanup trap exits).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 After a test run, screenshots appear in ./local-screenshots/<timestamp>/ on the host
- [x] #2 After a test run, build/UITestResults.xcresult exists on the host and can be opened in Xcode
- [x] #3 Retrieval happens even when xcodebuild exits non-zero
- [x] #4 Host paths are printed at the end of the script output
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Aligned the artifact retrieval in `scripts/run-ui-tests-in-vm.sh` to the exact contract.

The script's `cleanup()` (registered via `trap cleanup EXIT INT TERM`) now scp's, before the VM is stopped:
- the result bundle `/tmp/jobhunt-uitest.xcresult` → `build/UITestResults.xcresult` (rm -rf'd first so the latest run is always at that fixed path) — AC#2
- the guest screenshots `/tmp/jobhunt-screenshots/<timestamp>/` → `local-screenshots/<timestamp>/` (using the scp `:/path/.` content-copy form so the timestamped subdirs land directly under `local-screenshots/`, not nested under a `jobhunt-screenshots/` parent) — AC#1

Because retrieval runs in the EXIT trap, it executes even when xcodebuild exits non-zero — AC#3. Both host paths are logged via `log "xcresult → …"` / `log "screenshots → …"` — AC#4.

Also: added `local-screenshots/` to `.gitignore` (build/ was already ignored), and updated `docs/vm-testing.md` (Teardown + artifact-paths sections) to the new paths.

Note: prior to this task the script copied to `build/vm-results/` — the functionality (EXIT-trap retrieval of both artifacts with logged paths) already existed; this change just renames the destinations to the documented `build/UITestResults.xcresult` + `local-screenshots/<timestamp>/` contract. Verified `bash -n` clean.
<!-- SECTION:FINAL_SUMMARY:END -->
