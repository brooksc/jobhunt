---
id: TASK-492
title: '"Process Selected" should unpause the queue (run-now intent)'
status: Done
assignee: []
created_date: '2026-06-18 19:17'
updated_date: '2026-06-18 19:17'
labels:
  - bug
  - ux
  - queue
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When the queue is paused and the user right-clicks a queued request and chooses "Process Selected", the rows reset to queued but nothing runs — the drain loop bails while paused, so the user has to click Resume. "Process Selected" is an explicit run-now intent and should clear the pause.

Fix: in LLMQueueView.processSelected, if the queue is paused, resume it (which unpauses + starts the drain) instead of calling startProcessing into a paused queue.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Process Selected on a paused queue runs the selected requests without a separate Resume click
- [x] #2 The pause toggle reflects the now-resumed state
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LLMQueueView.processSelected now resumes the queue when it's paused (resumeQueue unpauses + starts the drain), so "Process Selected" honors the run-now intent instead of leaving the reset rows queued behind a pause. Build-verified.
<!-- SECTION:FINAL_SUMMARY:END -->
