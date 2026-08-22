---
id: TASK-688
title: 'MCP silently unavailable after relaunch — no token written, bridge dead'
status: To Do
assignee: []
created_date: '2026-08-22 04:03'
labels:
  - bug
  - mcp
  - silent-failure
dependencies: []
priority: high
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed 2026-08-21 on the running Debug-DMG build: ~/.jobhunt-mcp-token does not exist, and POST /mcp/jobs/list returns nothing. Earlier the same day the file was present (19:11) and MCP calls worked — several were used to re-drive extractions. Something about a later relaunch left no token, and nothing said so.

The generation site is JobhuntApp.swift:124:

    if plan.needsMCPToken {
      #if !MAS_BUILD
        do { mcpToken = try MCPTokenManager.generateAndWrite() }
        catch { NSLog("MCP token setup failed — MCP will be unavailable: \(error)") }
      #endif
    }

Two ways this ends with a dead bridge and no user-visible signal:
- generateAndWrite throws: caught, NSLogged, and the app continues with an empty token. The server then answers /mcp/* with 503 'MCP not configured'. Nothing in the UI mentions it.
- plan.needsMCPToken is false for the launch: same outcome, no signal.

This matters because the MCP bridge is how third-party AI clients act on the user's data — the user drives Codex against it. A silent outage looks like 'the tools stopped working' with nothing to diagnose from. It is also the exact failure class the codebase has repeatedly fixed elsewhere (TASK-382/387/584: don't swallow a failure that leaves a subsystem dead).

Not yet diagnosed: which of the two branches fired, and why the file is absent rather than stale. The NSLog produced no entry in  for the process, which itself suggests the throw never happened and the token simply wasn't requested — worth confirming before fixing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A launch that ends without a usable MCP token surfaces that state to the user rather than only NSLog
- [ ] #2 The root cause of the missing token on this build is identified
- [ ] #3 Settings shows whether MCP is currently available, since that is where a user would look
<!-- AC:END -->
