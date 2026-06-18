---
id: TASK-487
title: Add a Clear button to the LLM Queue Completed section header
status: Done
assignee: []
created_date: '2026-06-18 18:00'
updated_date: '2026-06-18 18:00'
labels:
  - ux
  - llm-queue
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The "Clear Completed" action existed only as an easy-to-miss icon button in the top-right toolbar. Add a discoverable "Clear" button directly in the Completed section header on the LLM Queue screen, reusing the existing clearCompleted() (deletes all finished rows: Done / Failed / Exhausted / Cancelled).

Files: app/Views/Queue/LLMQueueView.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Completed section header shows a Clear button
- [x] #2 Clicking it removes all finished requests (reuses clearCompleted)
- [x] #3 The button is disabled when there are no completed requests
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added a "Clear" button (trash.slash + label) to the Completed pane header in LLMQueueView via a new optional `clearAction` parameter on the `queuePane` helper (passed only for the Completed pane). It reuses the existing `clearCompleted()` → `queueActor.clearCompleted()`, so it deletes every finished row (Done / Failed / Exhausted / Cancelled), and is `.disabled(!hasCompletedRequests)` so it greys out when there's nothing to clear. The pre-existing top-right toolbar "Clear Completed" icon is kept. Build-verified (Jobhunt-DMG); no new logic (UI affordance over existing tested action).
<!-- SECTION:FINAL_SUMMARY:END -->
