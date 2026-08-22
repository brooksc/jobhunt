---
id: TASK-688
title: 'MCP silently unavailable after relaunch — no token written, bridge dead'
status: To Do
assignee: []
created_date: '2026-08-22 04:03'
updated_date: '2026-08-22 18:54'
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
- [x] #1 A launch that ends without a usable MCP token surfaces that state to the user rather than only NSLog
- [x] #2 The root cause of the missing token on this build is identified
- [x] #3 Settings shows whether MCP is currently available, since that is where a user would look
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Root cause: two overlapping instances. Shutdown deleted ~/.jobhunt-mcp-token unconditionally, so when a second launch overwrote the file with its own token and the first instance then quit, the LIVE app was left serving a token nothing could read. Matches the evidence — two Jobhunt processes were observed during a rebuild, and shortly after the file was absent while the app ran and /mcp/* answered nothing. The bridge recovered on the next clean relaunch, which is why it looked transient.

- MCPTokenManager.deleteIfOurs(_:at:) deletes only when the file still holds this launch's token; a stale token is harmless, a deleted live one is not. 5 tests, including the two-instance case and the over-permissive-file case.
- AppServices keeps the launch's token so shutdown can prove ownership.
- Settings > Debug now reports the MCP BRIDGE rather than file existence: file-existence alone reported 'Present' for a stale token left by another instance — precisely when the bridge is broken — and said nothing about why. It now distinguishes 'not started this launch', 'token file missing', and 'replaced by another running copy'.

not verified: (visual) — the Debug row's three states have not been seen rendered.
<!-- SECTION:NOTES:END -->
