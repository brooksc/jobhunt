---
id: TASK-647
title: >-
  ServerTests: flaky connection reset after the >1MB capture test poisons the
  next request
status: Done
assignee: []
created_date: '2026-07-25 21:34'
updated_date: '2026-08-09 19:20'
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
- [x] #1 No ServerTest can inherit a connection left by another — including, but not limited to, the >1MB capture test
- [x] #2 Any retry is limited to transport-level URLErrors and never masks an assertion failure
- [x] #3 The suite passes repeatedly (12 consecutive runs) with tests in the current order
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-09: reopened. The first fix — an ephemeral session for the >1MB test only — passed 10 consecutive local runs and then failed on CI immediately (run 31330335321, commit f969ed65) with the SAME -1005 'network connection was lost', but in a DIFFERENT test: `testCaptureRoute_storeError_returnsInternalError` (JobhuntServerTests.swift:853). So the large body was never the cause, only the case that happened to be observed. The real cause is `URLSession.shared` pooling keep-alive connections to a shared NWListener server that closes them; any test can inherit a dead one. Fixing it properly means no test reusing a pooled connection.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All 33 request sites in `JobhuntServerTests` now go through `HTTPTestClient`, which creates an ephemeral `URLSession` per request and invalidates it immediately. No connection is ever reused.

**The first attempt was wrong, and CI caught it within minutes.** I isolated only the >1MB capture test, on the report's theory that the large body poisoned the pool. It passed 10 consecutive local runs — then CI run 31330335321 failed a *different* test, `testCaptureRoute_storeError_returnsInternalError` (line 853), with the same `-1005 "The network connection was lost"`. Body size was never the cause. `URLSession.shared` keeps connections alive and hands them on; ServerTests share one `JobhuntServer` deliberately (NWListener port lifecycle) and that server closes them, so *any* test could inherit a dead one. The original report's diagnosis — and mine — mistook the observed instance for the mechanism.

**Still no retry.** One able to swallow a transport error can swallow a real regression, and would have concealed both of these rather than surfacing them.

**Verified: 12 consecutive full ServerTests runs, 12 passed / 0 failed** (57 tests each), plus swiftlint clean.

Worth recording: an intermediate run of that same loop reported 12/12 *failures*, which turned out to be a compile break I had just introduced by renaming the helper with a regex that missed the multi-line call form. The loop is what caught it — a single run would have been the only signal, and I had already seen one pass.
<!-- SECTION:FINAL_SUMMARY:END -->
