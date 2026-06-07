---
id: TASK-055
title: 'LLM Queue screen: request table, attempt history, batch controls, pause/resume'
status: To Do
assignee: []
created_date: '2026-06-07 22:49'
labels:
  - swift-rewrite
  - ui
  - screen
milestone: m-1
dependencies:
  - TASK-045
  - TASK-044
documentation:
  - swift-plan.md
  - static/screens/llm_queue.jsx
priority: medium
ordinal: 3200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the LLM Queue monitoring/management screen.

## Read first
- swift-plan.md §10.2 #8 (LLM Queue behavior), §8.6 (queue model + events).
- Legacy static/screens/llm_queue.jsx (720 lines) — request table (type/status/model/duration/error), filters (all/extract/fit, by status), expandable errors + attempt history, batch actions (process selected, enqueue all, cancel selected, cancel all, reset), global pause/resume, manual run.

## Implement (app/Views/Queue/)
- Table from LLMRequest/LLMRequestAttempt via @Query; live updates from the engine's event stream (task-044); filters; expandable attempt history; batch select + process/enqueue-all/cancel/cancel-all/reset via QueueActor; pause/resume toggle; manual run.

## Dependencies
Depends on task-045 (shell) and task-044 (QueueActor + events). 

## Tests (AppUITests)
- Pause/resume reflects in sidebar indicator; reset a failed request re-queues; cancel removes; attempt history expands; filter by type/status.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Request table with type/status/model/duration/error + filters
- [ ] #2 Expandable attempt history per request
- [ ] #3 Batch process/enqueue-all/cancel/cancel-all/reset + pause/resume + manual run via QueueActor
- [ ] #4 Live updates from engine event stream; XCUITest covers pause/reset/cancel/filter
<!-- AC:END -->
