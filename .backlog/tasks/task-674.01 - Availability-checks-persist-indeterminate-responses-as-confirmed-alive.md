---
id: TASK-674.01
title: Availability checks persist indeterminate responses as confirmed alive
status: Done
assignee: []
created_date: '2026-08-21 20:26'
updated_date: '2026-08-22 03:37'
labels:
  - bug
  - availability
  - data-integrity
dependencies: []
references:
  - TASK-674
  - core/Services/AvailabilityChecker.swift
modified_files:
  - core/Services/AvailabilityChecker.swift
  - core/Services/AvailabilityVerdict.swift
  - tests/CoreTests/AvailabilityCheckerTests.swift
  - tests/CoreTests/AvailabilityOutcomeRecordingTests.swift
parent_task_id: TASK-674
priority: high
type: bug
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regression found during the 2026-08-21 code review. Several outcomes that mean only 'not proven gone'—including timeouts, authentication walls, ambiguous Workday responses, malformed or unresolved LinkedIn URLs, empty responses, and unexpected HTTP statuses—are promoted to confirmed alive. The persisted history and completion UI can therefore claim a posting is still listed without affirmative evidence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Only an affirmative response that identifies a live posting produces an alive verdict
- [ ] #2 Timeouts, cancellations, authentication walls, non-HTTP responses, and ambiguous ATS responses produce an unverified verdict
- [ ] #3 LinkedIn checks with no resolvable posting ID, empty or undecodable bodies, or unexpected statuses produce an unverified verdict
- [ ] #4 Indeterminate outcomes do not increase the confirmed checked count or permit an all-clear message
- [ ] #5 End-to-end tests assert persisted unverified verdicts for every indeterminate response class
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: Codex
created: 2026-08-21 20:42
---
Mapped to the 2026-08-21 whole-codebase health review finding: availability vocabulary collapses unknown or indeterminate outcomes into confirmed alive state.
---
<!-- COMMENTS:END -->
