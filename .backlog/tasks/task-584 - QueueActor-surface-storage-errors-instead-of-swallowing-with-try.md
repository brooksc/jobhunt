---
id: TASK-584
title: 'QueueActor: surface storage errors instead of swallowing with try?'
status: Done
assignee: []
created_date: '2026-07-02 21:51'
updated_date: '2026-07-22 01:18'
labels: []
dependencies: []
references:
  - 'core/LLM/QueueActor.swift:473'
  - 'core/LLM/QueueActor.swift:506'
  - 'core/LLM/QueueActor.swift:225-249'
  - 'core/LLM/QueueActor.swift:767-822'
priority: medium
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Problem:** `QueueActor.swift` has ~19 `try? await store.…` call sites that silently discard errors. Two are correctness bugs, the rest degrade diagnostics:

- **Line 473** — post-transition verification fetch uses `try?`, so if the store throws, `current` is `nil` and the request is classified as `.cancelled`. A real storage failure masquerades as a user cancellation and is never surfaced.
- **Line 506** — same pattern; a store error is reclassified as `.providerFailure`, which can feed the auto-pause logic with a wrong signal.
- **Lines 225/236/243/249** — `reconcileOrphanedFitScores()` failures are silently dropped; a failed reconcile can leave a job's fit mirror stuck in "Scoring…" indefinitely (the exact risk TASK-527 documented).
- **Lines 767/782/805/822/933** — `recordAttempt` / `markFitScoreFailed` / `markFitScoreRunning` silently fail, leaving gaps in attempt history with no trace.

**How to fix:**
1. Add a small private helper `func logStoreFailure(_ error: Error, context: String)` on `QueueActor` that calls `logger.error(...)` and optionally emits a `queueError` event via the existing notification mechanism.
2. Replace the two correctness-critical `try?` calls (lines 473, 506) with `do { … } catch { logStoreFailure(error, context: "…") }` that returns a distinct outcome (or re-throws to the caller).
3. Replace the remaining `try?` mirror/attempt calls with `try { … } catch { logStoreFailure(error, context: "…") }` so failures appear in logs and diagnostics reports.

**Note:** Do NOT add recovery logic — just make failures visible. The existing retry/auto-pause path handles transient provider issues; this is about store failures being invisible.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No `try? await store.` call site in QueueActor.swift silently discards an error without at least a log statement
- [ ] #2 A simulated store failure during request transition returns a distinct outcome (not .cancelled) and logs an error
- [ ] #3 Existing CoreTests pass; no new test infrastructure required beyond verifying the log call
<!-- AC:END -->
