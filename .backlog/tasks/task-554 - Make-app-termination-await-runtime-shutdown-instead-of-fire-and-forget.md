---
id: TASK-554
title: Make app termination await runtime shutdown instead of fire-and-forget
status: To Do
assignee: []
created_date: '2026-06-19 23:49'
labels:
  - audit
  - lifecycle
  - shutdown
  - server
dependencies: []
references:
  - 'app/JobhuntApp.swift:203'
  - 'app/Shell/AppServices.swift:133'
  - 'server/swift/JobhuntServer.swift:199'
  - TASK-530
modified_files:
  - app/JobhuntApp.swift
  - app/Shell/AppServices.swift
  - server/swift/JobhuntServer.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: app termination currently handles `NSApplication.willTerminateNotification` from the SwiftUI view tree, calls `integration.stop()`, then launches `Task { await services.shutdown() }` without awaiting that task (`app/JobhuntApp.swift:203`). `AppServices.shutdown()` awaits `server.stop()` (`app/Shell/AppServices.swift:133`), and `JobhuntServer.stop()` itself waits for the NWListener cancelled state before returning (`server/swift/JobhuntServer.swift:199`). That careful stop contract can be bypassed because the process may continue termination before the detached shutdown task reaches completion.

Why important: shutdown is the lifecycle boundary that releases the local server port, cancels background work, and will likely become the place that removes the transient MCP token (`TASK-530`). Fire-and-forget termination makes clean teardown timing dependent on process-exit behavior instead of the app-owned lifecycle contract. This can create intermittent restart/port/token cleanup behavior and makes shutdown hard to test reliably.

Suggested implementation: move termination ownership to an `NSApplicationDelegate` or equivalent app-level coordinator that can start shutdown earlier and make the sequencing explicit. At minimum, centralize termination into a single `AppServices.shutdownForTermination()` path that stops `PlatformIntegration`, awaits service shutdown, and invokes MCP token cleanup from `TASK-530`. Add a lifecycle test around the shutdown coordinator where possible; if direct AppKit termination is hard to test, factor the shutdown sequence into a testable async method and verify ordering.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Termination shutdown is owned by an app-level coordinator rather than a fire-and-forget SwiftUI `.onReceive` task.
- [ ] #2 The shutdown sequence awaits local server stop before considering teardown complete in the testable coordinator path.
- [ ] #3 The shutdown sequence provides a clear hook for MCP token deletion from `TASK-530`.
<!-- AC:END -->
