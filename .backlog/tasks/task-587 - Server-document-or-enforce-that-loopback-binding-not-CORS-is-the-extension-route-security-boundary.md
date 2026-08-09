---
id: TASK-587
title: >-
  Server: document or enforce that loopback binding (not CORS) is the
  extension-route security boundary
status: Done
assignee: []
created_date: '2026-07-02 21:51'
updated_date: '2026-08-09 20:07'
labels: []
dependencies: []
references:
  - 'server/swift/JobhuntServer.swift:510'
priority: low
ordinal: 36000
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
- [x] #1 Either: a code comment above isAllowedExtensionOrigin explains the security model and CLAUDE.md CORS section is updated; OR extension routes require a token equivalent to MCP routes
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Took option 1, the task's own recommendation: document it rather than add a token.

A "SECURITY MODEL" block above `isAllowedExtensionOrigin` now states plainly that **the loopback binding is the boundary and CORS is not** — `Origin` is forgeable by any local process, while `requiredInterfaceType = .loopback` is enforced by the OS before a request is parsed. It spells out what follows: extension routes are protected against the network and *not* against a hostile process running as this user, which is deliberate because such a process could read the SwiftData store directly. It also says what the origin allowlist genuinely is for — stopping *other Chrome extensions* driving these routes from the browser, where same-origin makes `Origin` trustworthy — and why MCP routes do carry a token (third-party AI clients, so the token scopes who may act on the user's data).

**Found and fixed alongside:** the CLAUDE.md CORS note was stale. It claimed the allowlist "is empty during development (permits all `chrome-extension://` origins); add the CWS ID after publishing". The published ID has been in `productionExtensionOrigin` for some time, and the arbitrary-origin permission is now a debug-build flag with release failing closed. Anyone reading that note would have had the wrong model of both the boundary and the current state.

No token was added. If a hostile-localhost threat model ever matters, the recorded fix is a launch-time shared secret handed to the extension at port discovery — a stricter origin list would not help, since the problem is that `Origin` is not evidence.
<!-- SECTION:FINAL_SUMMARY:END -->
