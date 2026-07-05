---
id: TASK-597
title: >-
  llm: surface a persistent banner when the queue is blocked by a
  missing/unconfigured AI provider
status: Done
assignee: []
created_date: '2026-07-05 18:57'
labels:
  - llm
  - queue
dependencies: []
modified_files:
  - app/Platform/PlatformIntegration.swift
  - core/LLM/QueueActor.swift
  - tests/CoreTests/QueueBackfillTests.swift
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A user's API key got cleared. Processing a new job then failed silently: the Extract request sat at "Queued" with no error/warning that the key was missing. Unlike a rejected key (HTTP 401, TASK-542) — which shows a persistent app-wide banner — the "provider not configured" state produced only a transient, no-attention OS notification and no in-app banner, so a queue blocked by a missing key looked identical to an idle queue.

Two causes:
1. In PlatformIntegration.handleEvent, `.providerNotConfigured` did nothing (`break`) — it never set the persistent `router.queueAlert` banner the 401 path sets.
2. QueueActor debounced `.providerNotConfigured` to once per unconfigured episode (`didEmitNotConfigured`, TASK-483). Once it fired (easily missed), enqueuing a new job never re-surfaced it — and because the app subscribes to queue events after launch (AsyncStream drops events with no subscriber), a launch-time emit could be missed entirely.

Fix:
- PlatformIntegration now sets a persistent, cross-screen `QueueAlert` (showsAISettings: true) for `.providerNotConfigured`, mirroring the 401 treatment. Cleared on dismiss or when the queue next succeeds (jobReady already nils queueAlert).
- QueueActor re-arms the debounce whenever new user-initiated work is enqueued (new `onWorkEnqueued()` used by enqueue/enqueueFit/enqueueFitForActiveResumes), so actively processing a job while unconfigured reliably re-emits the notice + banner. Bulk enqueues (one array) still produce a single notice.

Known limitation / tradeoff: this deliberately relaxes TASK-483's strict once-per-episode debounce for user-initiated enqueues — a stream of individual captures while unconfigured can now yield one notice each (the persistent banner is the primary channel; the OS notification is secondary). The message is generic ("AI provider isn't set up…") because AIReadiness bundles missing model / missing key / missing consent; it doesn't distinguish which.</description>
<parameter name="acceptanceCriteria">["When the queue is blocked because the provider isn't configured, a persistent app-wide banner appears with a one-click jump to AI Provider settings", "Enqueuing new work while unconfigured re-emits .providerNotConfigured (re-arms the per-episode debounce) so the banner reliably reappears", "A bulk enqueue (single array) emits the notice once, not once per job", "CoreTests green (new re-emit test); app builds; SwiftLint/SwiftFormat clean"]
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
.providerNotConfigured now sets the same persistent QueueAlert banner as the 401 path (PlatformIntegration), and QueueActor re-arms the once-per-episode debounce on each new enqueue via onWorkEnqueued() so a blocked queue reliably shows an actionable, cross-screen warning instead of sitting silently at 'Queued'. Added a deterministic CoreTests regression (QueueNotConfiguredReEmitTests) proving the emit + re-arm; app builds; lint/format clean.
<!-- SECTION:FINAL_SUMMARY:END -->
