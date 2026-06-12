---
id: TASK-249
title: >-
  Queue UI: Keep paused state synchronized with persisted settings after
  completion events
status: To Do
assignee: []
created_date: '2026-06-12 02:21'
labels:
  - queue
  - ux
  - state
dependencies: []
references:
  - app/Views/Queue/LLMQueueView.swift
  - core/LLM/QueueActor.swift
  - core/Settings/SettingsStore.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLMQueueView sets local isPaused to false on every processingComplete event, regardless of the persisted queue pause setting. This can make the UI show resumed while settings remain paused or while the user paused during processing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queue view derives paused state from SettingsStore or refreshes it after queue events.
- [ ] #2 processingComplete does not override a user pause.
- [ ] #3 Auto-pause, manual pause, resume, and completion states remain consistent across toolbar/menu/settings.
- [ ] #4 Tests or UI checks cover pause during processing followed by completion.
<!-- AC:END -->
