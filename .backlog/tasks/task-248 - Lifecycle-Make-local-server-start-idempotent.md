---
id: TASK-248
title: 'Lifecycle: Make local server start idempotent'
status: Done
assignee: []
created_date: '2026-06-12 02:21'
updated_date: '2026-06-12 02:27'
labels:
  - lifecycle
  - server
  - concurrency
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - app/ContentView.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobhuntServer.start() always creates a new listener and can overwrite listener state if called while already running. Make start idempotent or explicitly stop before restart so UI retry paths cannot create orphan listeners.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Calling start() on an already-running server is a no-op or returns the existing port.
- [ ] #2 Retry UI cannot create multiple active listeners for one server instance.
- [ ] #3 Tests cover repeated start() calls and stop() cleanup.
- [ ] #4 ServerRunning/serverError UI state remains accurate after retry.
<!-- AC:END -->
