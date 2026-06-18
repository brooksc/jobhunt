---
id: TASK-483
title: Upfront notice when a capture lands but no AI provider is configured
status: Done
assignee: []
created_date: '2026-06-18 02:45'
updated_date: '2026-06-18 03:15'
labels:
  - notifications
  - ux
  - onboarding
  - workflow
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Today there is no proactive signal when the user captures a job but has no AI provider configured. The pending extraction request just fails on each attempt, and only after a consecutive-failure streak does `QueueActor` emit `.autoPaused` → a critical "AI Queue Paused — auto-paused after repeated failures" notification (PlatformIntegration). So the user learns about it reactively, with a "paused" message rather than "set up an AI provider."

Desired (per docs/workflow.md step 3): when a capture is ingested and no provider/API key is configured (distinct from a configured-but-failing provider), notify the user immediately — e.g. "Job captured ✓ — set up an AI provider in Settings → AI Provider to enable extraction & fit scoring" — and deep-link to AI Provider settings. Keep the existing auto-pause behavior for runtime failures of a configured provider.

Consider: detect "no provider configured" at ingest (or first queue pick-up) by checking the provider/key state (KeychainStore / SettingsStore) rather than letting it fail N times first. Avoid notification spam — one notice while unconfigured, not one per capture.

References: core/LLM/QueueActor.swift, core/Settings/SettingsStore.swift, core/Settings/KeychainStore.swift, app/Platform/PlatformIntegration.swift, docs/workflow.md (step 3).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 When a capture is ingested with no AI provider/API key configured, the user gets an immediate notice (not after a failure streak)
- [x] #2 The notice deep-links to Settings → AI Provider (or focuses that screen)
- [x] #3 It is distinct in wording from the runtime 'AI Queue Paused' auto-pause notification
- [x] #4 No notification spam: at most one 'no provider configured' notice while unconfigured, regardless of how many captures queue up
- [x] #5 Existing auto-pause-on-repeated-failures for a configured-but-failing provider is unchanged
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
When work is queued but no usable AI provider is configured, the user now gets an immediate, deep-linked notice instead of waiting for the failure-streak auto-pause.

Implementation:
- `LLMProviderFactory.requiresAPIKey(provider:)` — true for the hosted providers (openai/anthropic/google/openrouter); false for LM Studio default + custom (local/self-hosted, reachability only knowable by trying).
- `QueueActor` gained an `isProviderConfigured` closure (defaulted to `{ true }` so the many existing call sites/tests are unaffected) and a new `.providerNotConfigured` event. In the drain loop, when there's queued work but `!isProviderConfigured()`, it emits the event **once per unconfigured episode** (a `didEmitNotConfigured` flag, cleared on the first configured drain) and `break`s — leaving the work queued rather than failing it into an auto-pause (AC#1, AC#4, AC#5: the configured-but-failing auto-pause path is untouched).
- `AppServices` wires `isProviderConfigured` to: not key-requiring, or a non-empty Keychain key for the selected provider.
- `PlatformIntegration` turns `.providerNotConfigured` into a "Set up an AI provider" notification whose click deep-links to `Settings` (AC#2), with wording distinct from the "AI Queue Paused" auto-pause notice (AC#3). `LLMQueueView`'s event switch handles the new case (no-op there).

Tests (CoreTests/ExtractionEngineTests): `testProviderNotConfigured_emitsNoticeAndLeavesWorkQueued` (emits the event, request stays `.queued`, queue not paused, provider never invoked) and `testProviderNotConfigured_isDebouncedAcrossDrains` (exactly one notice across two unconfigured drains). Full fast gate green; app builds.

Scope note: "not configured" is intentionally the unambiguous case — a key-requiring provider with an empty key. A local provider that's merely unreachable is not flagged up front (you can't know without trying); it still surfaces via the existing auto-pause-on-failure.
<!-- SECTION:FINAL_SUMMARY:END -->
