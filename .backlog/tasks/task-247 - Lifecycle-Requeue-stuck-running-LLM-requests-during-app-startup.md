---
id: TASK-247
title: 'Lifecycle: Requeue stuck running LLM requests during app startup'
status: To Do
assignee: []
created_date: '2026-06-12 02:20'
labels:
  - lifecycle
  - queue
  - recovery
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - app/JobhuntApp.swift
  - app/Shell/AppServices.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QueueActor has requeueRunningOnLaunch(), but app startup does not call it. Requests left running after a crash or quit can remain stuck forever. Wire startup recovery and surface any failures.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 App startup calls requeueRunningOnLaunch before or during queue initialization.
- [ ] #2 Running requests from previous sessions are reset to queued with stale startedAt/error cleared.
- [ ] #3 Startup recovery failures are surfaced through diagnostics or a visible queue error.
- [ ] #4 Tests or launch harness cover a running request being requeued on startup.
<!-- AC:END -->
