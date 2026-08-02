---
id: TASK-657
title: >-
  Nothing reaps LLM requests orphaned in 'running' while the app is up, and the
  failure leaves no trace
status: To Do
assignee: []
created_date: '2026-08-02 18:05'
labels:
  - llm-queue
  - reliability
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed live on 2026-08-02: request `E924E97F-F965-43F1-9C1B-1FADB64FF9AB` (type `fit`, job #732, resume 5, `deepseek/deepseek-v4-flash` via OpenRouter) sat in `running` for 11+ minutes.

It was **not** in flight — `lsof -a -p <app> -i` showed the app holding **no** outbound connection. The HTTP call had long since ended; the row was simply never transitioned out of `running`.

**Defect 1 — no reaper while the app is running.** `QueueActor.requeueRunningOnLaunch()` is the only thing that rescues a stuck `running` row, and it fires at launch (`AppServices.swift:113`) or from the Debug tab button (`DebugTab.swift:145`). A row orphaned mid-session sits there until the user notices and restarts, or finds a button in a Debug tab most users will never open.

Worse than the stalled job: **each orphan permanently leaks a slot from the adaptive concurrency pool.** One is invisible (the other three jobs captured in the same batch completed normally). Several would silently throttle the queue toward serial, presenting as "the LLM queue is slow" with no error anywhere — the same symptom already chased once this cycle and misattributed to OpenRouter rate limiting.

**Defect 2 — the failure path recorded nothing.** `LLMRequest.error` was empty and `ZLLMREQUESTATTEMPT` had no row, so there is no evidence of what killed it. Whatever path lost this request neither wrote an attempt row nor set an error, which makes the root cause undiagnosable after the fact.

Note `llm_timeout` is unset in the store, so the default 300s applied — and the row still outlived it by 6 minutes. `URLRequest.timeoutInterval` bounds the gap *between packets*, not total duration, so it is not a backstop for a request that stalls after receiving some bytes. Don't assume the transport timeout will cover this.

**Direction**
- Reap on a timer, not only at launch: a `running` row older than some multiple of `llmTimeout` goes back to `queued` (reusing `requeueAfterCancellation`'s guard so an inner cancellation that already set a terminal status stays authoritative).
- Bound total request duration independently of `timeoutInterval`, so a stalled stream terminates rather than hanging forever.
- Always write an attempt row / error on the way out of `running`, so the next orphan leaves evidence.
- Surface a non-Debug signal when a request is reaped — the current failure is entirely silent.

**Repro is opportunistic** (it wasn't deliberately induced), so a unit test should drive the reaper directly: insert a `running` row with an old `startedAt`, tick the reaper, assert it returns to `queued` and the concurrency slot is released.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A request left in 'running' past a duration bound is returned to 'queued' while the app stays running, with no user action
- [ ] #2 A reaped request releases its adaptive-concurrency slot, so repeated orphans cannot throttle the queue
- [ ] #3 A request cannot exceed a total wall-clock bound even if the connection trickles bytes (timeoutInterval alone is insufficient)
- [ ] #4 Every exit from 'running' writes an attempt row or an error, so an orphan leaves diagnosable evidence
- [ ] #5 A reap is visible outside the Debug tab
- [ ] #6 Unit test: a 'running' row with a stale startedAt is requeued by the reaper and its slot freed
- [ ] #7 A cancellation that already set a terminal status is not overwritten by the reaper
<!-- AC:END -->
