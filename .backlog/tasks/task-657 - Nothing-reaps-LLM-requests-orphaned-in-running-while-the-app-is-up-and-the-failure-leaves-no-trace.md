---
id: TASK-657
title: >-
  LLM queue wedges: batch barrier + isRunning guard mean one slow request stalls
  everything, unrecoverable without a relaunch
status: To Do
assignee: []
created_date: '2026-08-02 18:05'
updated_date: '2026-08-06 22:26'
labels:
  - llm-queue
  - reliability
dependencies: []
priority: high
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
- [x] #3 A request cannot exceed a total wall-clock bound even if the connection trickles bytes (timeoutInterval alone is insufficient)
- [ ] #4 Every exit from 'running' writes an attempt row or an error, so an orphan leaves diagnosable evidence
- [ ] #5 A reap is visible outside the Debug tab
- [ ] #6 Unit test: a 'running' row with a stale startedAt is requeued by the reaper and its slot freed
- [ ] #7 A cancellation that already set a terminal status is not overwritten by the reaper
- [ ] #8 A slow request no longer blocks queued work: new requests start as soon as a slot frees, without waiting for the whole batch
- [x] #9 A wedged drain can be recovered from the UI without quitting the app
- [x] #10 Every request has a total wall-clock bound, independent of URLRequest.timeoutInterval, after which it is cancelled and requeued
- [x] #11 cancelProcessing() cannot hang indefinitely on a child task that ignores cancellation
- [ ] #12 Test: a task group containing one never-returning task does not prevent remaining queued requests from being dispatched
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**2026-08-02, second incident — root cause is structural, not just orphaned rows.** The user reported the queue stuck again and, critically, that **restarting it from the UI did nothing; only quitting and relaunching the app recovered it.** Store snapshot mid-incident: 3 `running`, 7 `queued`, 3 `succeeded` — all six started rows stamped the same `startedAt` (the relaunch), with no progress on the seven behind them.

Three code-level causes, all confirmed by reading `QueueActor.startProcessing()`:

**1. Batch barrier (`QueueActor.swift:407`).** The loop fetches up to `limit` queued rows, dispatches them in a `withTaskGroup`, and awaits the *entire group* before fetching the next batch. Free slots go unused while the batch's slowest member finishes, and one task that never returns stalls every remaining queued request indefinitely. Measured this session: 13 fit requests, fastest 16s, mean 61s, slowest **139s** — so even in perfect health a batch runs at its worst case, and five requests finishing in 20s wait two minutes for the sixth. Much of the reported 'stuck' feeling is this, with no failure involved.

**2. `guard !isRunning else { return }` (`QueueActor.swift:354`).** While the loop is blocked inside the task group, `isRunning` stays true, so every later `startProcessing()` is a silent no-op. This is exactly why the UI restart did nothing and only a relaunch worked. The guard makes a wedged drain indistinguishable from a healthy one, and unrecoverable in-process.

**3. `cancelProcessing()` awaits `task.value` (`QueueActor.swift:344`).** It cancels the drain and waits for it to exit. A child blocked in a non-cancellable await hangs this too, so the clean-shutdown path can wedge on the same condition — relevant to `RestoreCoordinator`, which calls `AppServices.shutdown()` before a destructive swap.

**There is no total-duration timeout anywhere.** No `withTimeout` / deadline exists in `core/LLM/` or `core/Services/`. The only bound is `URLRequest.timeoutInterval = settings.llmTimeout` (unset in the live store, so the **300s** default). That measures the gap *between packets*, not total duration, so a response that trickles never trips it — and with legitimate requests running 16–139s, a 5-minute inter-packet timeout would essentially never fire even when something is genuinely wrong. Nothing retries on timeout at the queue level.

**Correction to the first incident's evidence.** I inferred 'not in flight' from `lsof -a -p <pid> -i` showing no outbound sockets. That inference is unsafe: during this incident requests completed successfully while `lsof` showed no ESTABLISHED sockets for the app. Whatever the reason (short-lived connections between polls, or connections not attributed to the process by `lsof`), **absence of sockets is not evidence a request is dead.** The orphaned-row conclusion from the first incident stands on the 11-minute duration and the fact that only a requeue cleared it, not on the socket check.

**Recommended fix, in order:**
1. **Replace the batch barrier with continuous dispatch** — keep `limit` tasks in flight, starting a new request as each finishes. This alone removes most of the stalling and raises throughput at no cost.
2. **Per-request total-duration timeout** — cancel and requeue past a wall-clock bound independent of `timeoutInterval`. Given the 139s observed maximum, a bound around 5-10x the mean is defensible; make it derive from `llmTimeout` rather than adding a second setting.
3. **Make a wedged drain recoverable in-process** — `isRunning` must not be able to block restart forever. Either track drain liveness with a heartbeat and let a stale drain be superseded, or have restart cancel the existing drain first.
4. Then the reaper and the error-capture work already described above.

**Fixed the unrecoverable part (commit `f96ae375`); the throughput part is deliberately still open.**

Root cause confirmed in use, not just by reading: work queued, provider configured with a valid key, queue **not** paused, nothing running, and the UI control doing nothing. That is the `isRunning` no-op path.

What misled the diagnosis for a long time: the LLM Queue toolbar button permanently reads "Resume Queue" whether or not the queue is paused, so it looked like a stuck pause. It is an unconditional `processAll()` action — [TASK-667], now corrected to describe the right control.

Shipped:

1. **Per-request wall-clock deadline.** Every request races a timeout derived from the user's `llmTimeout` (x1.5), cancelled and requeued if it outlives it. `URLRequest.timeoutInterval` could never cover this: it bounds the gap *between packets*, so a trickling response or a continuation that never resumes runs forever. `llmTimeout` is now carried on `ExtractionSettings` (defaulted, so no call site changed).
2. **Stall recovery.** The drain stamps a heartbeat each pass; a start that finds a drain quiet beyond `drainStallSeconds` (15 min, comfortably above the request deadline) cancels it and takes over, emitting a `queueError` so the user is told rather than left guessing. `isRunning` can no longer wedge the queue permanently.

Seven tests in `QueueDeadlineTests`: a never-returning operation is cancelled promptly; work inside budget is untouched; the operation's own error is not masked by the deadline (misclassifying a provider failure as a timeout would corrupt retry logic); the deadline is derived from the setting and survives an unset one; the stall threshold sits above the request deadline; concurrent starts still don't duplicate a healthy drain.

**Still open — the batch barrier.** `withTaskGroup` awaits the whole batch before fetching more, so free slots idle while the slowest member finishes, and throughput runs at the worst case (measured 16s fastest, 139s slowest in one batch). That is now a latency cost rather than a correctness one: with requests bounded, a slow member can no longer wedge anything. Worth doing, but it is a real rewrite of the drain loop and did not belong in the same change as the safety fix.
<!-- SECTION:NOTES:END -->
