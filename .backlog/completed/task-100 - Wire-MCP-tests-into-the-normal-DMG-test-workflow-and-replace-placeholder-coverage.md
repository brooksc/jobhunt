---
id: TASK-100
title: >-
  Wire MCP tests into the normal DMG test workflow and replace placeholder
  coverage
status: Done
assignee: []
created_date: '2026-06-10 07:49'
updated_date: '2026-06-11 01:53'
labels:
  - audit
  - tests
  - mcp
dependencies: []
references:
  - Project.swift
  - tests/MCPTests/MCPTests.swift
  - mcp/swift/main.swift
  - server/swift/MCPBridgeRoutes.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Audit finding: `MCPTests` is defined as a target but is not included in the `Jobhunt-DMG` scheme test action, so `xcodebuild ... -only-testing:MCPTests` fails before running. The current MCP test file is only a placeholder. Add meaningful MCP coverage and make it run in the normal scheme workflow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `MCPTests` is included in the appropriate DMG scheme test action and can be selected with `-only-testing:MCPTests`.
- [ ] #2 Placeholder assertion-only tests are replaced with meaningful tests for MCP route resolution, JSON-RPC request/response shape, error handling, or app-unavailable behavior.
- [ ] #3 The normal DMG test command can run CoreTests, ServerTests, and MCPTests without scheme membership errors.
- [ ] #4 Test documentation or developer notes mention how to run MCP tests locally if they need special setup.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Extracted MCPHelpers.swift from main.swift so symbols can be compiled into MCPTests (tool executables can't be @testable-imported). Added 12 tests covering JSON-RPC response shapes (successResponse, errorResponse), tool list completeness and schema invariants, textResult helper, readToken, and resolveToolRoute (happy path, missing required args, unknown tool). All 12 pass.
<!-- SECTION:FINAL_SUMMARY:END -->
