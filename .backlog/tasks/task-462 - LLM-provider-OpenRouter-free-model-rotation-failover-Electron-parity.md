---
id: TASK-462
title: 'LLM provider: OpenRouter free-model rotation + failover (Electron parity)'
status: To Do
assignee: []
created_date: '2026-06-14 04:39'
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
- [ ] #1 llmOpenRouterFreeRotate setting (SettingsKey + SettingsStore accessor) exists with a checkbox in the Settings LLM tab, default off
- [ ] #2 OpenRouterModelPool fetches /models, filters to free structured-output models, and caches with a 1h TTL; the filter logic is unit-tested against a captured /models JSON fixture
- [ ] #3 When rotation is enabled, OpenRouterProvider tries models in round-robin and fails over to the next model on error/empty/429, up to N (~4) distinct models; when disabled it uses the single configured model unchanged
- [ ] #4 A request that rotation eventually recovers counts as zero queue failures; a request that exhausts all rotation candidates counts as exactly one failure (no premature auto-pause from per-model attempts)
- [ ] #5 Manual/LLMEval run with a real OpenRouter key: extraction works through rotation and demonstrably fails over from a failing free model
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Verified with a real OpenRouter API key: rotation + failover observed; rotation-off path unchanged
- [ ] #2 Free-model filter unit-tested against a captured current /models JSON fixture (shape may have drifted since Electron)
<!-- DOD:END -->
