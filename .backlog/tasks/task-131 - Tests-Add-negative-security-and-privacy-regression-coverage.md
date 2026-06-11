---
id: TASK-131
title: 'Tests: Add negative security and privacy regression coverage'
status: To Do
assignee: []
created_date: '2026-06-11 03:26'
labels:
  - tests
  - security
  - privacy
  - server
  - mcp
  - llm
dependencies: []
references:
  - tests/ServerTests/JobhuntServerTests.swift
  - tests/MCPTests/MCPTests.swift
  - tests/CoreTests/SettingsStoreTests.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - server/swift/JobhuntServer.swift
  - server/swift/MCPBridgeRoutes.swift
  - core/LLM/QueueActor.swift
  - core/Settings/ConsentHelper.swift
  - >-
    .backlog/tasks/task-122 -
    Security-Restrict-local-HTTP-server-CORS-loopback-binding-and-mutating-route-auth.md
  - >-
    .backlog/tasks/task-123 -
    Security-Require-non-empty-MCP-token-and-wire-token-generation-into-app-server-startup.md
  - >-
    .backlog/tasks/task-124 -
    Privacy-Enforce-cloud-LLM-consent-in-the-provider-execution-path.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The suite currently covers local HTTP, MCP helper, and consent happy paths, but not abuse cases found by the security/privacy audit. Add tests that fail for broad CORS, missing/wrong auth, empty MCP tokens, and cloud LLM execution without consent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Server tests reject disallowed origins and unauthenticated mutating local HTTP requests.
- [ ] #2 Server/MCP tests cover missing, empty, wrong, and correct MCP token cases.
- [ ] #3 LLM queue/provider tests prove cloud provider execution is blocked without consent and allowed with consent.
- [ ] #4 Existing tests no longer encode wildcard CORS or unauthenticated mutating routes as expected behavior.
- [ ] #5 Tests are linked to the relevant security/privacy backlog tasks so implementation and verification stay aligned.
<!-- AC:END -->
