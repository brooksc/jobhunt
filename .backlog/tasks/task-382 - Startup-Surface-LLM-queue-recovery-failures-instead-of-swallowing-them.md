---
id: TASK-382
title: 'Startup: Surface LLM queue recovery failures instead of swallowing them'
status: To Do
assignee: []
created_date: '2026-06-12 22:55'
labels:
  - audit
  - concurrency
  - startup
  - diagnostics
  - llm-queue
dependencies: []
references:
  - app/Shell/AppServices.swift
  - core/LLM/QueueActor.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppServices starts queue.requeueRunningOnLaunch() with try?, so failures leave running requests stuck without user-visible diagnostics or a retry path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Startup queue recovery failures are recorded in diagnostics and surfaced to the user or Debug tab.
- [ ] #2 A retry path exists or the queue view clearly reports unrecovered stuck requests.
- [ ] #3 Tests cover failed requeueRunningOnLaunch behavior or a simulated diagnostic event.
<!-- AC:END -->
