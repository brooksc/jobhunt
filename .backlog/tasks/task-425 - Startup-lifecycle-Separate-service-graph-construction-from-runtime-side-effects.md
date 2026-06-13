---
id: TASK-425
title: >-
  Startup lifecycle: Separate service graph construction from runtime side
  effects
status: To Do
assignee: []
created_date: '2026-06-13 04:33'
labels:
  - audit
  - startup
  - architecture
dependencies: []
references:
  - app/Shell/AppServices.swift
  - app/JobhuntApp.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`AppServices.init(modelContainer:)` currently constructs services and immediately performs runtime side effects: generating/writing the MCP token in non-MAS builds, starting the local HTTP server, requeueing launch-time LLM work, registering a notification observer, and running availability checks. Any launch mode that needs the service graph also receives these side effects, which has already leaked into fixture generation and makes tests/previews harder to isolate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Constructing the app service graph does not start the HTTP server, generate/write MCP tokens, run queue recovery, register launch observers, or run availability checks.
- [ ] #2 Runtime side effects are started by an explicit lifecycle method or owner that takes a launch/runtime mode.
- [ ] #3 Production launch still starts the expected runtime services exactly once.
- [ ] #4 Fixture generation, UI-test setup, and other non-production modes can opt out of user-machine side effects.
- [ ] #5 Add focused coverage or lifecycle tests that would fail if service construction alone starts runtime side effects.
<!-- AC:END -->
