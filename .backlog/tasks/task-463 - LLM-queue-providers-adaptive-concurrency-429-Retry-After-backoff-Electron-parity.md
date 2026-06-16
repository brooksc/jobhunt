---
id: TASK-463
title: >-
  LLM queue/providers: adaptive concurrency + 429 Retry-After backoff (Electron
  parity)
status: Done
assignee: []
created_date: '2026-06-14 04:40'
updated_date: '2026-06-16 23:40'
labels:
  - llm
  - provider
  - electron-parity
  - phase-5
  - concurrency
  - llm-queue
dependencies: []
references:
  - core/LLM/Providers/OpenAICompatibleTransport.swift
  - core/LLM/Providers/GoogleProvider.swift
  - core/LLM/QueueActor.swift
  - core/LLM/LLMProvider.swift
  - core/LLM/Providers/OpenAIProvider.swift
  - core/LLM/Providers/OpenRouterProvider.swift
  - >-
    server/extract.js@8c438ca (onRateLimit/onSuccess/CONCURRENCY_PROMOTE_AFTER
    ~1144-1178; 429 parsing 155-160, 248-263)
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context
Electron tracked RUNTIME concurrency that dropped to 1 on HTTP 429 (`onRateLimit`) and promoted back up after 10 consecutive successes (`CONCURRENCY_PROMOTE_AFTER`), starting hosted=5 / google+apple=1 (`server/extract.js` ~1144-1178). It also parsed 429 bodies / `Retry-After` to sleep the right amount (OpenAI-compat: parse "retry...Ns", extract.js 155-160; Google: up to 4 RL retries with parsed delay, extract.js 248-263).

Swift uses a FIXED per-provider `concurrencyLimit` (OpenAI/Google/OpenRouter=3, Anthropic/Custom=2, LMStudio/Foundation=1) read fresh each loop (`QueueActor.swift:253`) but NEVER changed. 429 is thrown as a plain `httpError(statusCode:429)` with no Retry-After parsing (OpenAICompatibleTransport.swift:79-82; GoogleProvider treats any non-2xx as a hard error, GoogleProvider.swift:70-72). The generic QueueActor exponential backoff (2^attempt capped 30s) then applies.

## What to change (how)
### A. 429 Retry-After honoring
1. Add `LLMProviderError.rateLimited(retryAfter: TimeInterval?)` (core/LLM/LLMProvider.swift).
2. In `OpenAICompatibleTransport`, on 429 (currently lines 79-82) parse the `Retry-After` response header (seconds or HTTP-date) and/or a "retry in Ns" pattern in the body, and throw `.rateLimited(retryAfter:)`.
3. In `QueueActor`'s retry/backoff path, when the error is `.rateLimited`, sleep for the provided `retryAfter` (clamped to a sane max) instead of the generic exponential backoff.
4. `GoogleProvider` (own request path): add a bounded rate-limit retry budget (e.g. up to 4) that parses the Gemini 429 delay and sleeps, like Electron.

### B. Adaptive runtime concurrency
1. Introduce a mutable per-session effective concurrency in `QueueActor` (separate from the provider's STATIC `concurrencyLimit`, which becomes the CEILING). Initialize to `provider.concurrencyLimit`.
2. On any in-flight 429, drop the effective limit to 1. After K (e.g. 10) consecutive successes, step it back up one toward the ceiling.
3. Use this effective value where `provider.concurrencyLimit` is currently read (QueueActor.swift:253). Reset on relaunch (no persistence).
4. Optional/judgement: Electron's hosted ceiling was 5; Swift caps hosted at 3. Decide whether to raise OpenAI/OpenRouter ceilings toward 5 and DOCUMENT the decision.

## Risk / verification
Live keys + the ability to trigger 429 (hard to reproduce deterministically). UNIT-test the pieces in isolation: (a) the Retry-After/body parser; (b) the adaptive-concurrency state machine as a pure function — feed synthetic 429/success sequences and assert the effective limit drops to 1 on 429 then promotes to the ceiling after K successes. Manual: hammer a low-rate provider and confirm backoff respects Retry-After.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 LLMProviderError gains a rate-limited case carrying an optional retryAfter; OpenAICompatibleTransport parses Retry-After header / 'retry in Ns' body on 429 and throws it
- [x] #2 QueueActor honors the parsed retryAfter for 429 (clamped) instead of generic exponential backoff
- [x] #3 GoogleProvider has its own bounded (~4) rate-limit retry that parses the Gemini delay
- [x] #4 QueueActor uses an effective runtime concurrency that drops to 1 on a 429 and promotes back toward the provider ceiling after K (~10) consecutive successes; implemented as a pure, unit-tested state machine
- [x] #5 No behavior change when no 429s occur (effective concurrency == provider ceiling)
- [x] #6 Decision on raising hosted concurrency ceilings (Electron used 5) is made and documented in the task notes
- [x] #7 Retry-After parser and adaptive-concurrency state machine each have isolated unit tests with synthetic inputs
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#6 decision: hosted concurrency ceilings stay at 3 (OpenAI/OpenRouter/Google), NOT raised to Electron's 5. Rationale: the new adaptive drop-to-1-then-recover handles rate-limit bursts, and bumping the ceiling risks more 429s with no measured benefit at this app's scale (consistent with the project's "don't over-optimize" convention). DoD#2 (manual verification against a real provider that returns 429) is NOT done — a live 429 isn't reproducible here; the pure parser + state machine are unit-tested with synthetic 429/success sequences instead (DoD#1).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
429 Retry-After: added `LLMProviderError.rateLimited(retryAfter:)` + a pure `RetryAfterParser` (header delta-seconds/HTTP-date, Gemini `retryDelay`, OpenAI "retry in Ns"). OpenAICompatibleTransport throws `.rateLimited` on 429; `QueueActor.backoffMs` honors the parsed delay (clamped to 60s) over exponential backoff, and a 429 is classified as a transient `.rateLimited` outcome — requeued but NOT counted toward the auto-pause streak (so a rate-limit burst can't trip auto-pause). GoogleProvider (its own request path) got a bounded 4-retry budget that parses the Gemini delay then throws `.rateLimited`. Adaptive concurrency: `AdaptiveConcurrency` pure state machine (ceiling = provider.concurrencyLimit, drops to 1 on 429, +1 per 10 consecutive successes); QueueActor dispatches at the effective value, re-seeds on ceiling change, resets each session; no behavior change with no 429s (AC#5). AC#6: ceilings kept at 3 (documented). AC#7/DoD#1: RetryAfterParserTests + AdaptiveConcurrencyTests + QueueBackoffTests (18 tests, synthetic sequences). Full fast gate (797) green; app builds. PENDING (DoD#2): manual verification against a real 429 — not reproducible in this environment.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Retry-After parser and adaptive-concurrency state machine covered by isolated unit tests (synthetic 429/success sequences)
- [ ] #2 Manually verified backoff respects Retry-After against a real provider that returns 429
<!-- DOD:END -->
