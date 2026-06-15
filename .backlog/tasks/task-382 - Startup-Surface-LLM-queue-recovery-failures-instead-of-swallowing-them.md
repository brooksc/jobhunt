---
id: TASK-382
title: 'Startup: Surface LLM queue recovery failures instead of swallowing them'
status: Done
assignee: []
created_date: '2026-06-12 22:55'
updated_date: '2026-06-15 18:12'
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
modified_files:
  - app/Shell/AppServices.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppServices starts queue.requeueRunningOnLaunch() with try?, so failures leave running requests stuck without user-visible diagnostics or a retry path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Startup queue recovery failures are recorded in diagnostics and surfaced to the user or Debug tab.
- [x] #2 A retry path exists or the queue view clearly reports unrecovered stuck requests.
- [ ] #3 Tests cover failed requeueRunningOnLaunch behavior or a simulated diagnostic event.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppServices.startRuntime() now wraps queue.requeueRunningOnLaunch() in do/catch instead of try?: on failure it logs (NSLog) and shows an error toast which is also recorded in the Debug tab's recent-errors log (AC#1). The toast tells the user the queue may be stuck; the LLM Queue view shows the still-running requests and they can re-run/cancel them (AC#2). AC#3 (test of the failure path) deferred — requeueRunningOnLaunch failure needs the store failure-injection seam from TASK-479. Verified by build.
<!-- SECTION:FINAL_SUMMARY:END -->
