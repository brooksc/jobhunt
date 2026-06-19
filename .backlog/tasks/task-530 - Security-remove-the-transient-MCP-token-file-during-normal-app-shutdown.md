---
id: TASK-530
title: 'Security: remove the transient MCP token file during normal app shutdown'
status: To Do
assignee: []
created_date: '2026-06-19 04:51'
labels:
  - audit
  - security
  - mcp
  - token
  - local-server
dependencies: []
references:
  - app/JobhuntApp.swift
  - app/Shell/AppServices.swift
  - core/Settings/MCPTokenManager.swift
  - core/App/LaunchMode.swift
  - CLAUDE.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: the app generates a fresh MCP token at launch and writes it to `~/.jobhunt-mcp-token` with owner-only permissions, and `MCPTokenManager.delete()` exists. However, normal app shutdown calls `AppServices.shutdown()` and stops the server without deleting the token file. The token is described as transient, but it remains on disk after the server exits until the next launch overwrites it or something explicitly removes it.

Why this matters: the token protects the localhost MCP HTTP bridge. Leaving stale credentials on disk expands the window for accidental disclosure and makes the file's lifecycle differ from the documented "transient" behavior. Even though file permissions are strict and the server token rotates on launch, least-privilege cleanup should remove auth material when the service that accepts it is stopped.

Suggested implementation: have the launch/runtime owner delete the MCP token during normal shutdown for modes that generated one. Avoid deleting unrelated user files in fixture modes that did not generate a token. Consider also deleting a stale token before writing a new one and adding a termination-path test or focused unit seam around token lifecycle.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Normal interactive app shutdown removes `~/.jobhunt-mcp-token` after stopping runtime services.
- [ ] #2 Modes that do not generate an MCP token do not delete or create the token file as a side effect.
- [ ] #3 A failed token generation still leaves MCP disabled and does not create a misleading token lifecycle state.
- [ ] #4 Tests or a small lifecycle seam verify generation and cleanup behavior without touching the user's real home directory.
- [ ] #5 Documentation/comments continue to describe the MCP token as transient and match actual behavior.
<!-- AC:END -->
