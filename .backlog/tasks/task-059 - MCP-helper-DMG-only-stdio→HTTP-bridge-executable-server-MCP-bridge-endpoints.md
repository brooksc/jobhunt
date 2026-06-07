---
id: TASK-059
title: >-
  MCP helper (DMG only): stdio→HTTP bridge executable + server MCP-bridge
  endpoints
status: To Do
assignee: []
created_date: '2026-06-07 22:50'
labels:
  - swift-rewrite
  - mcp
  - server
milestone: m-1
dependencies:
  - TASK-046
  - TASK-047
documentation:
  - swift-plan.md
  - server/mcp.js
  - tests/integration/mcp.test.js
priority: low
ordinal: 3600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Provide MCP access for DMG builds via a `jobhunt-mcp` stdio executable that bridges to the running app's localhost HTTP server (NOT opening the SwiftData store directly). Excluded from MAS.

## Read first
- swift-plan.md §11 (MCP stdio→HTTP bridge design), §7 (server MCP-bridge endpoints, token-gated, #if !MAS_BUILD), §4 (port discovery pattern).
- Legacy server/mcp.js — the 12 tools to reproduce: jobs_list, job_get, add_capture, update_job, set_job_status, add_job_note, rerun_extraction, list_sites, add_site, update_site, delete_site, workflow_snapshot.
- tests/integration/mcp.test.js.

## Implement
- In JobhuntServer (DMG only): add the MCP-bridge HTTP endpoints (one per tool) calling JobService/SiteService, bound to 127.0.0.1 and gated by a per-launch auth token the app writes to a known per-user file on startup.
- In JobhuntMCP (executable target, `#if !MAS_BUILD`): implement MCP over stdio (JSON-RPC framing — implement directly or via a vetted package). Each tool call → HTTP request to the app's bridge endpoint, authenticating with the token; discover the app's port by probing 8765–8769 + /api/ping (same as the extension).
- Bundle jobhunt-mcp in the DMG app (Contents/Helpers/); document the `claude mcp add node→/path/to/jobhunt-mcp` equivalent invocation in README.
- Behavior note: MCP works only while the app is running (single writer) — document this.

## Dependencies
Depends on task-047 (HTTP server + stubbed bridge extension point) and task-046 (services the endpoints call).

## Tests (MCPTests)
- Drive the executable with scripted stdio JSON against a stub HTTP server, asserting each tool's request/response (port mcp.test.js intent). One end-to-end test against the real app server (token auth + a real tool call).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 jobhunt-mcp implements all 12 tools over stdio, bridging to the app's HTTP server (no direct store access)
- [ ] #2 Server exposes token-gated MCP-bridge endpoints behind #if !MAS_BUILD, bound to 127.0.0.1
- [ ] #3 Helper discovers the app port (8765–8769 + /api/ping) and authenticates with the per-launch token
- [ ] #4 Bundled in the DMG app + documented claude mcp add usage; excluded from MAS
- [ ] #5 MCPTests: scripted stdio tool calls + one end-to-end test against the real server pass
<!-- AC:END -->
