---
id: TASK-535
title: 'LLM: persist model provenance as model IDs instead of provider IDs'
status: Done
assignee: []
created_date: '2026-06-19 04:56'
updated_date: '2026-06-21 03:26'
labels:
  - audit
  - llm
  - provider
  - provenance
  - fit-score
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Models/LLMRequestAttempt.swift
  - core/Models/JobFitScore.swift
  - core/Services/BackgroundStore.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - tests/CoreTests/QueueBackfillTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: the queue sends the configured model to providers, but several persisted records use `provider.id` where a model identifier is expected. In `QueueActor`, extraction and fit attempts set `LLMRequestAttempt.modelRequested` to `provider.id` (for example `openai`, `google`, `openrouter`) rather than the requested model. Successful fit scoring also saves `JobFitScore.model` as `provider.id`, while the request row separately records `fitOutput.modelReturned`.

Why this matters: model provenance is used for diagnostics, queue display, backfills, and understanding which model produced a score. Storing provider IDs in model fields makes the audit trail misleading and can cause backfill logic to recover `google` or `openai` as if they were model names. This is especially risky around OpenRouter rotation, where the configured model, rotated candidate, and returned model can differ.

Suggested implementation: separate provider identity from model identity. Persist the configured/requested model in `modelRequested`, persist the returned model in `modelReturned`, and save `JobFitScore.model` from the returned model when available. If provider identity is needed, add an explicit `providerID` field or store it in a clearly named provenance field rather than overloading model fields. For OpenRouter rotation, consider extending `ChatResponse` or provider instrumentation so the actual candidate model attempted can be recorded instead of only the configured setting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Successful extraction attempts record the requested model ID in `modelRequested`, not the provider ID.
- [ ] #2 Failed extraction and fit attempts record the model ID that would have been sent for that attempt when known.
- [ ] #3 Successful fit scoring stores `JobFitScore.model` as the returned model ID, falling back to the requested model only when the provider does not return one.
- [ ] #4 Provider identity is either stored in an explicitly named field or left out; it is not written into model fields.
- [ ] #5 Backfill tests are updated so historical provider-ID fallbacks are treated as legacy data, while new attempts assert real model IDs.
- [ ] #6 OpenRouter rotation behavior documents and tests what `modelRequested` means when the provider swaps candidate models internally.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Done (commits 88a58e7, d9ee23a). QueueActor no longer writes provider.id into model-provenance fields. modelRequested now = the configured model sent (extractSettings.llmModel / fitModel); modelReturned holds the provider's actual model (they differ under OpenRouter rotation). JobFitScore.model = returned model, falling back to configured. The fit pre-provider failure records nil rather than a provider id. extractSettings hoisted out of the do/catch so the failed-attempt record can reference the requested model. Provider identity is left out of model fields (not relabeled). Added a QueueActor-pipeline assertion in MockLLMInferenceTests (modelRequested == configured model, != provider id); QueueBackfill legacy fixtures unchanged and still pass. All targeted CoreTests green.
<!-- SECTION:FINAL_SUMMARY:END -->
