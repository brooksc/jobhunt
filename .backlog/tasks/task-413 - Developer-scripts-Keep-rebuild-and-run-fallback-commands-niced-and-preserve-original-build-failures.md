---
id: TASK-413
title: >-
  Developer scripts: Keep rebuild-and-run fallback commands niced and preserve
  original build failures
status: To Do
assignee: []
created_date: '2026-06-13 02:06'
labels:
  - audit
  - developer-workflow
  - scripts
  - tooling
dependencies: []
references:
  - scripts/rebuild-and-run.sh
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`scripts/rebuild-and-run.sh` wraps the primary xcodebuild commands in `nice`, but fallback commands after `xcbeautify` failure run without `nice` and can rerun a failed build/test rather than cleanly preserving the original failure. Make fallback behavior responsive-friendly and failure-transparent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All xcodebuild invocations in rebuild-and-run are launched with `nice`.
- [ ] #2 The script does not rerun a failed build/test merely because the build command failed; fallback is limited to formatter absence/failure handling as intended.
- [ ] #3 Failure output remains clear enough to diagnose the first failing build/test.
- [ ] #4 The script behavior is smoke-tested with and without xcbeautify available.
<!-- AC:END -->
