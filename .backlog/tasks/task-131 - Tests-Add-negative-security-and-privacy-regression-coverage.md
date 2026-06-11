---
id: TASK-131
title: 'Tests: Add negative security and privacy regression coverage'
status: Done
assignee: []
created_date: '2026-06-11 03:26'
updated_date: '2026-06-11 18:59'
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
modified_files:
  - tests/ServerTests/JobhuntServerTests.swift
  - tests/CoreTests/SettingsStoreTests.swift
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All negative security/privacy regression tests were already in place from TASK-122/123/124 work. Added task reference comments to link tests to their originating tasks: TASK-122 comments on CORS and origin-rejection tests in ServerTests, TASK-123 comments on MCP token auth tests, TASK-124/TASK-131 comment on ConsentHelperSnapshotTests. All 5 ACs satisfied: origin rejection (403), no-wildcard CORS, MCP token cases (wrong/empty/correct/unconfigured-503), cloud consent blocking, and task linkage.
<!-- SECTION:FINAL_SUMMARY:END -->
