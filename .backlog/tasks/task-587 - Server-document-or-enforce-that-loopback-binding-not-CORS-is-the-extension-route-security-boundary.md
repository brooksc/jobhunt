---
id: TASK-587
title: >-
  Server: document or enforce that loopback binding (not CORS) is the
  extension-route security boundary
status: To Do
assignee: []
created_date: '2026-07-02 21:51'
labels: []
dependencies: []
references:
  - 'server/swift/JobhuntServer.swift:510'
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Context:** Extension routes (`/captures`, `/site-reviews`, `/api/jobs/by-url`, `/api/app/focus`) are gated only by an `Origin: chrome-extension://…` header check (`JobhuntServer.swift:510–528`). Any local process can forge that header — the actual security boundary is the 127.0.0.1 loopback binding, not CORS. MCP routes require a bearer token; extension routes do not.

**This is a design decision, not necessarily a bug** — for a single-user localhost app, loopback-only is a reasonable boundary. But it should be an explicit, documented choice rather than an undocumented assumption.

**Two options (pick one):**
1. **Document it:** Add a comment block above `isAllowedExtensionOrigin` explaining that CORS here is a browser-side hint, not auth; loopback binding is the real guard. Update CLAUDE.md CORS section to note this.
2. **Add a shared secret:** Generate a session token at launch (like the MCP token), send it as a custom header from the extension (injected at capture time via a port-discovery response), and verify it on extension routes. Adds defense-in-depth at the cost of extension complexity.

**Recommendation:** Option 1 (document it) is sufficient for now. Option 2 if a hostile-localhost threat model matters.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Either: a code comment above isAllowedExtensionOrigin explains the security model and CLAUDE.md CORS section is updated; OR extension routes require a token equivalent to MCP routes
<!-- AC:END -->
