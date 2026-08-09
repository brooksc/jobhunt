---
id: TASK-647
title: >-
  ServerTests: flaky connection reset after the >1MB capture test poisons the
  next request
status: Done
assignee: []
created_date: '2026-07-25 21:34'
updated_date: '2026-08-09 18:56'
labels:
  - tests
  - ci
  - flaky
dependencies: []
references:
  - tests/ServerTests/JobhuntServerTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobhuntServerTests.testMCPCaptureAdd_acceptsStructuredDataArray` failed on CI run 30171362290 with a transport-level error, not an assertion:

    NSURLErrorDomain Code=-1005 "The network connection was lost"
    nw_socket_get_input_frames [C45:2] recvmsg(...) [54: Connection reset by peer]
    http://127.0.0.1:57585/mcp/captures/add

Re-running the same commit passed with no code change, confirming a flake.

Cause is ordering plus shared state: it runs immediately after `testMCPCaptureAdd_acceptsBodyOver1MB`, which pushes >1MB through the *shared* `JobhuntServer` instance (ServerTests deliberately share one instance via `static sharedServer` to avoid NWListener port-lifecycle problems — see CLAUDE.md). The large-body request appears to leave the connection in a state the next request inherits. The very next test hitting the same route passed in 9ms.

Not urgent — it costs an occasional CI re-run — but it erodes trust in a red build.

Options: have the large-body test not leave a poisoned connection behind (e.g. its own URLSession, or explicitly invalidate the session afterwards); or retry once specifically on a transport-level URLError, kept clearly distinct from an assertion failure so real regressions can never be masked.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The >1MB capture test cannot leave a connection state that affects the following test
- [x] #2 Any retry is limited to transport-level URLErrors and never masks an assertion failure
- [x] #3 The suite passes repeatedly (e.g. 10 consecutive runs) with tests in the current order
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`testMCPCaptureAdd_acceptsBodyOver1MB` now uses a dedicated ephemeral `URLSession`, invalidated in a `defer`, so its connection never returns to the shared pool the next test draws from.

Every test in the suite used `URLSession.shared`. Pushing ~2.1 MB through it left a connection that the following test inherited and the server then reset — the `-1005 / Connection reset by peer` failure on CI run 30171362290, which passed on re-run with no code change. ServerTests share one `JobhuntServer` on purpose (NWListener port lifecycle), so the client side is the only thing that can be isolated.

**No retry was added.** A retry able to swallow a transport error can also swallow a real regression; isolating the connection is both cheaper and exact, which satisfies criterion 2 by construction rather than by policing.

**Verified: 10 consecutive full ServerTests runs, 10 passed / 0 failed**, tests in their current order (57 tests per run).
<!-- SECTION:FINAL_SUMMARY:END -->
