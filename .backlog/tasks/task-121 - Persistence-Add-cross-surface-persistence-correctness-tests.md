---
id: TASK-121
title: 'Persistence: Add cross-surface persistence correctness tests'
status: To Do
assignee: []
created_date: '2026-06-11 02:47'
labels:
  - persistence
  - tests
  - swiftdata
  - mcp
dependencies: []
references:
  - tests/CoreTests/JobServiceTests.swift
  - tests/CoreTests/SettingsStoreTests.swift
  - tests/ServerTests/JobhuntServerTests.swift
  - tests/MCPTests
  - server/swift/MCPBridgeRoutes.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The current test suite covers basic service and server flows, but the highest-risk persistence behavior lacks targeted coverage: concurrent capture ingestion, atomic capture/job/queue creation, settings visibility across runtime services, saved-search persistence, view-service parity, and MCP DTO compatibility. Add focused tests that protect the data-flow boundaries identified in the persistence audit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tests cover concurrent capture ingestion and verify unique sequential job numbers or the intended collision-safe behavior
- [ ] #2 Tests cover atomic capture/job/queue creation without orphaned rows on failure
- [ ] #3 Tests cover settings mutation visibility between UI-facing settings and queue/provider runtime behavior
- [ ] #4 Tests cover saved-search persistence and deletion through the chosen service path
- [ ] #5 Tests cover MCP job/site read DTO compatibility through route or read-model tests
<!-- AC:END -->
