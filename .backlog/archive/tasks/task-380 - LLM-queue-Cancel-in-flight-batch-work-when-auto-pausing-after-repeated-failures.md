---
id: TASK-380
title: >-
  LLM queue: Cancel in-flight batch work when auto-pausing after repeated
  failures
status: To Do
assignee: []
created_date: '2026-06-12 22:55'
labels:
  - audit
  - concurrency
  - llm-queue
  - auto-pause
dependencies: []
references:
  - core/LLM/QueueActor.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QueueActor auto-pauses after a failure threshold, but the current task group has already launched every request in the batch and does not cancel outstanding work when the threshold is reached.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Auto-pause cancels remaining task-group work where cancellation is meaningful.
- [ ] #2 Provider/extraction paths check cancellation before expensive or side-effecting work where practical.
- [ ] #3 Tests cover a mixed batch where auto-pause stops additional queued work from being completed.
<!-- AC:END -->
