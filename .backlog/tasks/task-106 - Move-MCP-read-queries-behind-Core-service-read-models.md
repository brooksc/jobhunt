---
id: TASK-106
title: Move MCP read queries behind Core service read models
status: To Do
assignee: []
created_date: '2026-06-10 20:49'
labels:
  - architecture
  - audit
  - mcp
  - server
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
- [ ] #1 MCP jobs list, job get, sites list, and snapshot reads delegate to Core service query methods or read-model providers instead of constructing SwiftData fetch descriptors in route handlers.
- [ ] #2 Route handlers remain responsible for transport concerns only: auth, request decoding, response encoding, and status codes.
- [ ] #3 Core query/read-model methods are covered by focused tests independent of MCP transport.
- [ ] #4 Existing MCP response shapes remain compatible unless an intentional API change is documented.
<!-- AC:END -->
