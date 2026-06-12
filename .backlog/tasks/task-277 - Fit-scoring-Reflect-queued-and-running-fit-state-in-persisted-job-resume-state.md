---
id: TASK-277
title: >-
  Fit scoring: Reflect queued and running fit state in persisted job/resume
  state
status: To Do
assignee: []
created_date: '2026-06-12 03:34'
labels:
  - audit
  - fit-scoring
  - queue
  - ux
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Models/JobFitScore.swift
  - app/Views/Detail/JobDetailView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
enqueueFit creates LLMRequest rows but does not mark job or per-resume fit state as queued/running. The detail view relies on local isBusy, so background or restored queue work is not visible on the score cards.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queued/running fit work is visible for the affected job/resume pair after navigation or app restart.
- [ ] #2 Cancelling or failing fit work clears or updates that state consistently.
- [ ] #3 Tests cover enqueueing fit work and observing persisted queued/running status.
<!-- AC:END -->
