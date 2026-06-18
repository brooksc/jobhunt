---
id: TASK-483
title: Upfront notice when a capture lands but no AI provider is configured
status: To Do
assignee: []
created_date: '2026-06-18 02:45'
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
- [ ] #1 When a capture is ingested with no AI provider/API key configured, the user gets an immediate notice (not after a failure streak)
- [ ] #2 The notice deep-links to Settings → AI Provider (or focuses that screen)
- [ ] #3 It is distinct in wording from the runtime 'AI Queue Paused' auto-pause notification
- [ ] #4 No notification spam: at most one 'no provider configured' notice while unconfigured, regardless of how many captures queue up
- [ ] #5 Existing auto-pause-on-repeated-failures for a configured-but-failing provider is unchanged
<!-- AC:END -->
