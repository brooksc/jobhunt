---
id: TASK-168
title: 'Error handling: Surface local server startup failures'
status: To Do
assignee: []
created_date: '2026-06-11 21:43'
labels:
  - audit
  - error-handling
  - server
  - startup
dependencies: []
references:
  - app/Shell/AppServices.swift
  - app/Views/Settings/DebugTab.swift
  - tests/ServerTests
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`AppServices` starts the local `JobhuntServer` with `Task { try? await localServer.start() }`, so MCP/server startup failures are silently ignored. Track server startup state and surface failures through app diagnostics, settings, or the shared error reporter with a recovery path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Local server startup errors are captured instead of discarded.
- [ ] #2 The user can see whether the local server is running or failed, including a useful error message.
- [ ] #3 There is a retry or documented recovery path, with tests or a stubbed startup failure check.
<!-- AC:END -->
