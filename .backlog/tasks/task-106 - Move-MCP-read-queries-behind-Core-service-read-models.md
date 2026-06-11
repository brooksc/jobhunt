---
id: TASK-106
title: Move MCP read queries behind Core service read models
status: Done
assignee: []
created_date: '2026-06-10 20:49'
updated_date: '2026-06-11 02:48'
labels:
  - architecture
  - mcp
  - read-models
  - persistence
dependencies: []
references:
  - server/swift/MCPBridgeRoutes.swift
  - server/swift/JobhuntServer.swift
  - core/Services/JobService.swift
  - core/Services/SiteService.swift
  - core/Services/BackgroundStore.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Architecture audit finding: `MCPBridgeRoutes` mixes route handling with SwiftData fetch descriptors and model-to-DTO shaping. Write routes mostly use Core services, while read routes fetch `Job` and `Site` directly from `BackgroundStore`. Add Core service query/read-model methods so MCP routes only perform authentication, request decoding, and DTO translation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 MCP jobs list, job get, sites list, and snapshot reads delegate to Core service query methods or read-model providers instead of constructing SwiftData fetch descriptors in route handlers.
- [x] #2 Route handlers remain responsible for transport concerns only: auth, request decoding, response encoding, and status codes.
- [x] #3 Core query/read-model methods are covered by focused tests independent of MCP transport.
- [x] #4 Existing MCP response shapes remain compatible unless an intentional API change is documented.
- [x] #5 Read-model tests or route tests verify MCP job list, job get, sites list, and snapshot output remains stable after moving fetch/DTO shaping behind Core read-model methods
<!-- AC:END -->



## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Persistence/data-flow audit follow-up: MCP read routes still fetch SwiftData models and shape API DTOs inline in `server/swift/MCPBridgeRoutes.swift` (`handleMCPJobsList`, `handleMCPJobGet`, `handleMCPSitesList`, `handleMCPSnapshot`, and `resolveJobID`). This leaks persistence shape, enum raw values, relationship loading behavior, and date formatting into the transport layer. Keep this task as the backlog item for the audit finding "MCP/server read routes expose persistence shape as API shape."
<!-- SECTION:NOTES:END -->
