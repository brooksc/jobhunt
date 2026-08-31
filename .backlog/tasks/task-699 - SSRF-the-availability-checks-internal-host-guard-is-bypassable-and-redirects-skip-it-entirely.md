---
id: TASK-699
title: >-
  SSRF: the availability check's internal-host guard is bypassable, and
  redirects skip it entirely
status: To Do
assignee: []
created_date: '2026-08-31 19:24'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the 2026-08-31 security audit (`scratchpad/audit-security.md`, finding F1). **Verified independently** — all three legs of the attack path confirmed against the code.

## The path

`Job.applicationURL` is **LLM-extracted from job-posting text**, which is attacker-controlled. `JobURLPolicy.applicationURL` (`core/Services/JobURLPolicy.swift:22`) *prefers* it over the canonical and capture URLs, and the availability checker fetches it on a background loop that is **on by default**. The URL is scheme-validated but its host is not meaningfully validated.

## Two independent holes

**1. `isInternalHost` only recognises dotted-quad IPv4** (`core/Services/AvailabilityChecker.swift:356`). It splits on `.`, requires exactly 4 octets, and returns `false` otherwise. Every one of these resolves to loopback and is **not** blocked (verified by replicating the function's logic):

```
127.0.0.1          blocked ✓
127.1              blocked ✗   ← 2 octets, falls through
2130706433         blocked ✗   ← decimal form
0x7f.1             blocked ✗   ← hex form
017700000001       blocked ✗   ← octal form
::ffff:127.0.0.1   blocked ✗   ← IPv4-mapped IPv6; hits the ':' branch,
                                 matches none of ::1 / fe80 / fc / fd
```

The doc comment already concedes that hostnames *resolving* to private IPs aren't caught (DNS rebinding, accepted). These are different: they are **literals**, catchable without any resolution.

**2. Redirects bypass the guard completely.** `isInternalHost` is called exactly once — `AvailabilityChecker.swift:600`, on the *request* URL. There is no `willPerformHTTPRedirection` delegate anywhere in the file. Any allowed host can simply answer `302 Location: http://127.0.0.1:…` and URLSession follows it unguarded. This hole needs none of the parsing tricks above.

## Impact — genuinely exploitable, but bounded

Blind SSRF to loopback and private ranges from a background task, triggerable by getting a crafted posting into the user's library. No response body reaches the attacker, so it is a trigger primitive rather than an exfiltration one — it can hit state-changing GETs on whatever local services the user runs. Note Jobhunt's own server is on 127.0.0.1:8765-8769; MCP routes need a bearer token and extension routes check `Origin`, so those are defended, but other local dev servers may not be.

Rated High because it is remotely triggerable through normal use of a default-on feature, not because the blast radius is large.

## Fix

- Parse IP literals with `inet_pton` (AF_INET and AF_INET6) rather than string splitting, and check the resulting address against loopback/link-local/private/unique-local ranges. Handle IPv4-mapped IPv6 (`::ffff:0:0/96`) explicitly.
- Add a `URLSessionTaskDelegate` implementing `willPerformHTTPRedirection` that re-applies the guard to every hop and refuses the redirect otherwise. Cap the redirect chain.
- Add table-driven tests for every literal form above; they are cheap and this is exactly the class of bug that silently regresses.

Related: `git show 6ad9f4ed` fixed an earlier "SSRF-shaped host bypass" in discovery — check whether that guard shares this one's weakness or is already `inet_pton`-based, and unify them if they diverge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 isInternalHost blocks 127.1, 2130706433, 0x7f.1, octal forms and ::ffff:127.0.0.1, verified by table-driven tests
- [ ] #2 IP literals are parsed with inet_pton rather than string splitting
- [ ] #3 A willPerformHTTPRedirection delegate re-applies the guard on every redirect hop, with a capped chain
- [ ] #4 A redirect from an allowed host to 127.0.0.1 is refused, covered by a test
- [ ] #5 The discovery-side guard from 6ad9f4ed is checked for the same weakness and unified if it diverges
<!-- AC:END -->
