---
id: TASK-123
title: >-
  Security: Require non-empty MCP token and wire token generation into
  app/server startup
status: To Do
assignee: []
created_date: '2026-06-11 03:01'
updated_date: '2026-06-11 04:33'
labels:
  - security
  - mcp
  - server
  - startup
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - server/swift/MCPBridgeRoutes.swift
  - core/Settings/MCPTokenManager.swift
  - mcp/swift/MCPHelpers.swift
  - tests/MCPTests
  - tests/ServerTests/JobhuntServerTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MCP route authorization can fail open when the configured token is empty because missing Authorization parses as an empty string and matches the default empty mcpToken. The token manager exists, but app/server startup wiring was not evident in the audit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 JobhuntServer cannot be initialized or started with an empty MCP token in production paths.
- [ ] #2 MCPBridgeRoutes rejects requests when the configured token is empty, even if the request header is missing or empty.
- [ ] #3 App startup generates or loads the MCP token and passes it into the local server before MCP routes are available.
- [ ] #4 MCP helper reads the same token source used by the app/server handshake.
- [ ] #5 Tests cover missing, empty, wrong, and correct token cases.
- [ ] #6 MCP token file is created with explicit owner-only permissions, e.g. `0600`, and existing token files with broader permissions are repaired or rejected.
- [ ] #7 Tests or implementation checks verify weak token-file permissions are not accepted silently.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Security/privacy audit addendum: `MCPTokenManager.generateAndWrite()` writes `~/.jobhunt-mcp-token` via `String.write`, so file permissions depend on process umask. The token file should be created/read only when owned by the current user and mode-restricted.
<!-- SECTION:NOTES:END -->
