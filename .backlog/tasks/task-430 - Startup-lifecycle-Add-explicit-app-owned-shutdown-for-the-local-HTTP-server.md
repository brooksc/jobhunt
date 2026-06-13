---
id: TASK-430
title: 'Startup lifecycle: Add explicit app-owned shutdown for the local HTTP server'
status: To Do
assignee: []
created_date: '2026-06-13 04:34'
labels:
  - audit
  - startup
  - server
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - app/Shell/AppServices.swift
  - app/ContentView.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobhuntServer` has an async `stop()` method, but app lifecycle code never calls it and there is no scene/app termination owner around server startup and shutdown. Tests can stop the server, but production relies on process teardown. This makes future restart, multi-window, and lifecycle testing riskier.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The local HTTP server is owned by an app lifecycle component that starts it once and stops it on explicit shutdown or termination hooks where available.
- [ ] #2 The service-status retry flow cannot accidentally create conflicting server lifecycle state.
- [ ] #3 Existing production startup and server retry behavior continue to work.
- [ ] #4 Add focused tests or lifecycle seams that exercise server start/stop without launching the full SwiftUI app.
<!-- AC:END -->
