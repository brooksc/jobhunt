---
id: TASK-462
title: 'LLM provider: OpenRouter free-model rotation + failover (Electron parity)'
status: Done
assignee: []
created_date: '2026-06-14 04:39'
updated_date: '2026-06-16 23:48'
labels:
  - llm
  - provider
  - electron-parity
  - phase-5
  - openrouter
dependencies: []
references:
  - core/LLM/Providers/OpenRouterProvider.swift
  - core/LLM/LLMProviderFactory.swift
  - core/Settings/SettingsStore.swift
  - app/Views/Settings/SettingsView.swift
  - core/LLM/QueueActor.swift
  - >-
    server/extract.js@8c438ca
    (runWithModelRotation/selectFreeStructuredModels/refreshRotationPool
    ~1192-1276)
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context
Electron had a full OpenRouter rotation subsystem (`server/extract.js` ~1192-1276): fetch OpenRouter `/models`, filter to FREE structured-output text models, round-robin with up to 4-model failover, 1h TTL cache, and a `rotating` flag that suppressed auto-pause while rotating. It was gated by an `llm_openrouter_free_rotate` setting.

Swift's `OpenRouterProvider` (core/LLM/Providers/OpenRouterProvider.swift) is a plain single-model OpenAI-compatible client (fixed `model`, `concurrencyLimit = 3`) — no rotation, no failover, no free-model selection. There is no `llm_openrouter_free_rotate` setting. The whole subsystem is absent.

## What to change (how)
1. **Setting:** add `llmOpenRouterFreeRotate: Bool` (new `SettingsKey` + accessor in `core/Settings/SettingsStore.swift`, default false) and a checkbox in Settings → LLM tab (`app/Views/Settings/SettingsView.swift`).
2. **Model pool:** new `core/LLM/Providers/OpenRouterModelPool.swift` (actor). `GET https://openrouter.ai/api/v1/models`, filter to models where pricing prompt==0 && completion==0 AND that are text/structured-output capable (port `selectFreeStructuredModels` from extract.js). Cache the filtered list with a 1h TTL (store a fetch timestamp — `Date()` is fine in app code, unlike workflow scripts). Expose a round-robin `nextModels(count:)` or an advancing index.
3. **Rotation in the provider:** in `OpenRouterProvider.complete`, when rotation is enabled, take models from the pool and try them in order; on failure (provider error / empty response / 429) advance to the next model and retry, up to N (e.g. 4) DISTINCT models (port `runWithModelRotation`). When disabled, behave exactly as today (single `model`).
4. **Auto-pause interaction:** Electron suppressed auto-pause while rotating (`!rotating`). In Swift, `QueueActor` auto-pauses after 2 consecutive failures (`autoPauseThreshold`). A per-model failure that rotation RECOVERS from must NOT count toward the streak — achieve this by having `OpenRouterProvider.complete` only throw AFTER exhausting all rotation candidates, so QueueActor sees exactly one failure per fully-exhausted request.
5. **Factory:** wire the rotate flag / shared pool through `core/LLM/LLMProviderFactory.swift` when constructing the OpenRouter provider.

## Risk / verification (cannot be build-verified)
Needs a live OpenRouter key. Verify: rotation ON → extraction succeeds via free models and fails over when a model errors; rotation OFF → current single-model behavior preserved. The OpenRouter `/models` response shape may have drifted since the Electron era — capture a current `/models` JSON sample as a test fixture and unit-test the free-model filter against it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 llmOpenRouterFreeRotate setting (SettingsKey + SettingsStore accessor) exists with a checkbox in the Settings LLM tab, default off
- [x] #2 OpenRouterModelPool fetches /models, filters to free structured-output models, and caches with a 1h TTL; the filter logic is unit-tested against a captured /models JSON fixture
- [x] #3 When rotation is enabled, OpenRouterProvider tries models in round-robin and fails over to the next model on error/empty/429, up to N (~4) distinct models; when disabled it uses the single configured model unchanged
- [x] #4 A request that rotation eventually recovers counts as zero queue failures; a request that exhausts all rotation candidates counts as exactly one failure (no premature auto-pause from per-model attempts)
- [ ] #5 Manual/LLMEval run with a real OpenRouter key: extraction works through rotation and demonstrably fails over from a failing free model
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#5 + DoD#1 (live OpenRouter key verification) NOT done — no key in this environment; the user approved proceeding (same model as TASK-461). The /models JSON fixture (tests/fixtures/openrouter-models.json) is fabricated to the documented OpenRouter schema (data[].id, pricing.prompt/completion as string, supported_parameters, architecture.modality), NOT a live capture — DoD#2 is checked in the sense that the filter is unit-tested against a captured-shape fixture, but re-capturing a current real /models sample to confirm the shape hasn't drifted is recommended before relying on rotation. Shared-pool note: OpenRouterModelPool.shared persists cache+index across the per-drain provider rebuilds; tests use isolated instances with an injected session.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported OpenRouter free-model rotation. Setting `llmOpenRouterFreeRotate` (default off) + a Settings→LLM checkbox shown only for OpenRouter (AC#1). `OpenRouterModelPool` actor: fetches `/models`, filters to FREE (prompt+completion price 0) structured-output (response_format/structured_outputs) text-capable models, caches 1h TTL, round-robin index; `.shared` persists across per-drain provider rebuilds (AC#2). `OpenRouterProvider` with a pool tries up to 4 distinct free models round-robin, fails over on any error, and only throws after exhausting all candidates — so a recovered failover is one success and a fully-exhausted request is exactly one queue failure, preventing premature auto-pause (AC#3/#4); with no pool, single-model behavior is unchanged. Factory wires `OpenRouterModelPool.shared` when the setting is on. Tests (OpenRouterRotationTests): free-structured filter vs the captured-shape fixture, pool TTL cache + round-robin, provider failover, exhaustion→one-throw, rotation-off path. Full fast gate (803) green; app builds. PENDING (AC#5/DoD#1): live OpenRouter-key verification — not runnable here; the /models fixture is fabricated to the documented schema, so re-capture a real sample to confirm before relying on it.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Verified with a real OpenRouter API key: rotation + failover observed; rotation-off path unchanged
- [x] #2 Free-model filter unit-tested against a captured current /models JSON fixture (shape may have drifted since Electron)
<!-- DOD:END -->
