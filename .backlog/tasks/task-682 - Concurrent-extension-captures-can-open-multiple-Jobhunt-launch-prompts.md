---
id: TASK-682
title: Concurrent extension captures can open multiple Jobhunt launch prompts
status: Done
assignee: []
created_date: '2026-08-21 20:26'
updated_date: '2026-08-22 03:43'
labels:
  - bug
  - extension
  - concurrency
  - ux
dependencies: []
references:
  - TASK-489
  - extension/service_worker.js
  - extension/launch_app.js
modified_files:
  - extension/service_worker.js
  - extension/launch_app.js
  - extension/tests/test_launch_app.js
priority: medium
type: bug
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regression found during the 2026-08-21 code review. Concurrent capture handlers can each read an empty launch-cooldown timestamp before either records an attempt. Both then open the Jobhunt URL scheme, creating duplicate tabs and external-protocol prompts despite the advertised cooldown.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Concurrent capture attempts while Jobhunt is unavailable produce at most one URL-scheme launch
- [ ] #2 All concurrent callers share the result of the active launch attempt
- [ ] #3 The cooldown is effective before the launch operation waits for server readiness
- [ ] #4 A failed or timed-out launch leaves captures queued without causing an immediate burst of replacement prompts
- [ ] #5 A concurrent regression test uses overlapping promises and asserts exactly one URL open
<!-- AC:END -->
