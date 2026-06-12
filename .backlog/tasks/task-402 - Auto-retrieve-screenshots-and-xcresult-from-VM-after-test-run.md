---
id: TASK-402
title: Auto-retrieve screenshots and xcresult from VM after test run
status: To Do
assignee: []
created_date: '2026-06-12 23:53'
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
- [ ] #1 After a test run, screenshots appear in ./local-screenshots/<timestamp>/ on the host
- [ ] #2 After a test run, build/UITestResults.xcresult exists on the host and can be opened in Xcode
- [ ] #3 Retrieval happens even when xcodebuild exits non-zero
- [ ] #4 Host paths are printed at the end of the script output
<!-- AC:END -->
