---
id: TASK-673.01
title: Availability backlog drops pending jobs after the first batch
status: To Do
assignee: []
created_date: '2026-08-21 20:25'
labels:
  - bug
  - availability
  - background
dependencies: []
references:
  - TASK-673
  - core/Services/AvailabilityBacklog.swift
  - app/Shell/AppServices.swift
modified_files:
  - core/Services/AvailabilityBacklog.swift
  - app/Shell/AppServices.swift
  - tests/CoreTests/AvailabilityBacklogTests.swift
parent_task_id: TASK-673
priority: high
type: bug
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regression found during the 2026-08-21 code review. The background availability drain selects only the first bounded batch, but completing that batch can replace the entire pending queue. With more than one batch queued, untouched postings disappear and the app can report that drainage finished without checking them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Processing one batch preserves every pending job that was not part of that batch
- [ ] #2 Jobs from the processed batch leave the queue only after receiving a terminal availability outcome
- [ ] #3 Retryable outcomes from the processed batch remain queued without duplicating job IDs
- [ ] #4 The drain reports completion only after all originally pending and subsequently retryable jobs have been resolved
- [ ] #5 Regression coverage combines a pending set larger than the batch size with successive batch completion
<!-- AC:END -->
