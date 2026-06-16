---
id: TASK-430
title: 'Startup lifecycle: Add explicit app-owned shutdown for the local HTTP server'
status: Done
assignee: []
created_date: '2026-06-13 04:34'
updated_date: '2026-06-16 16:41'
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
- [x] #1 The local HTTP server is owned by an app lifecycle component that starts it once and stops it on explicit shutdown or termination hooks where available.
- [x] #2 The service-status retry flow cannot accidentally create conflicting server lifecycle state.
- [x] #3 Existing production startup and server retry behavior continue to work.
- [x] #4 Add focused tests or lifecycle seams that exercise server start/stop without launching the full SwiftUI app.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppServices now owns the server lifecycle end-to-end. AC#1: it starts the server once in `startRuntime()` (unchanged) and adds `shutdown()` — cancels the tracked runtime tasks and `await server.stop()` to release the port; JobhuntApp invokes `integration.stop()` + `services.shutdown()` on `NSApplication.willTerminateNotification` (best-effort, since process exit also frees the port). AC#2: `JobhuntServer.start()`/`startOnAnyPort()` are now idempotent (guard on `listener == nil`), so the Settings "Retry" flow can't bind a second conflicting listener; a failed start leaves `listener == nil` so retry-after-failure still proceeds. AC#3: production start path and retry behavior unchanged. AC#4: ServerTests exercise start/stop without the SwiftUI app — idempotent start (same port, no rebind) and start→stop→restart. ServerTests (31) green; app builds. Synergy with TASK-429 (`integration.stop()`).
<!-- SECTION:FINAL_SUMMARY:END -->
