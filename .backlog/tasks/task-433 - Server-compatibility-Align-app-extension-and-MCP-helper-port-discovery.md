---
id: TASK-433
title: 'Server compatibility: Align app, extension, and MCP helper port discovery'
status: Done
assignee: []
created_date: '2026-06-13 05:44'
updated_date: '2026-06-16 16:48'
labels:
  - audit
  - server
  - extension
  - mcp
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - extension/service_worker.js
  - mcp/swift/MCPHelpers.swift
  - chromestore/store-listing.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app server tries ports `8765...8784` and then an OS-assigned ephemeral port, while the Chrome extension and MCP helper probe only `8765...8769`. If the app binds to `8770+` or ephemeral, the server is running but companion clients report it missing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The app server, Chrome extension, MCP helper, docs, and store-listing text share one explicit port discovery contract.
- [x] #2 Companion clients can find every port the app may intentionally bind for normal production use, or the app no longer binds ports that clients cannot discover.
- [x] #3 The ephemeral fallback is either removed from production companion-server startup or paired with a discovery mechanism clients can use.
- [x] #4 Add focused tests or contract checks that would fail if app and client port lists drift again.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Introduced `ServerPortContract` in JobhuntCore as the single source of truth (ports 8765–8769) shared by all surfaces (AC#1). `JobhuntServer.start()` now binds only the contract ports and throws `ServerError.noPortAvailable` if all are taken — removing the OS-assigned ephemeral fallback that clients could never discover (AC#3); the failure surfaces in Settings → Local Server with Retry. `MCPHelpers.discoverPort()` references the same constant, so the two Swift surfaces can't drift. The extension `CANDIDATE_PORTS`, manifest `host_permissions`, and store-listing already used 8765–8769 (only the app over-bound) — annotated to reference the contract. AC#2 is satisfied by aligning the app down to the range every client probes. AC#4: ServerPortContractTests assert the contract value is deliberate and read the actual `extension/service_worker.js` + `extension/manifest.json` to verify their port lists match the contract — failing if any client drifts again. Decision noted: chose the clients' existing 8765–8769 (5 ports) over widening clients to the app's old 20-port range, minimizing blast radius (no extension re-publish). App + MCP build; CoreTests/ServerTests/MCPTests green.
<!-- SECTION:FINAL_SUMMARY:END -->
