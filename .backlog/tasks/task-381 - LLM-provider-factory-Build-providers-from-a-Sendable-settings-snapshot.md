---
id: TASK-381
title: 'LLM provider factory: Build providers from a Sendable settings snapshot'
status: Done
assignee: []
created_date: '2026-06-12 22:55'
updated_date: '2026-06-15 05:43'
labels:
  - audit
  - concurrency
  - settings
  - llm
dependencies: []
references:
  - app/Shell/AppServices.swift
  - core/LLM/LLMProviderFactory.swift
  - core/Settings/SettingsStore.swift
modified_files:
  - core/LLM/QueueActor.swift
  - app/Shell/AppServices.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QueueActor snapshots extraction settings on the main actor, but providerFactory captures SettingsStore directly and QueueActor calls it from the queue actor, crossing actor/thread boundaries with a non-Sendable observable settings object.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Provider construction uses a Sendable settings/API-key snapshot or is explicitly isolated to the main actor.
- [x] #2 Queue processing no longer reads live SettingsStore directly from QueueActor isolation.
- [x] #3 Tests or compiler checks cover provider selection from the snapshot.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
providerFactory was `@Sendable () -> any LLMProvider` and read the non-Sendable SettingsStore directly from QueueActor isolation — a data race on the settings cache (its siblings isPaused/onSetPaused/readExtractionSettings all hop to main). Changed it to `@Sendable () async -> any LLMProvider`; AppServices now builds the provider inside MainActor.run so SettingsStore is only touched on the main actor, and the built provider (LLMProvider: Sendable) crosses back to queue isolation safely. QueueActor awaits providerFactory() per drain pass. AC#3: covered by the compiler (strict concurrency) + existing ExtractionEngineTests/provider tests passing; sync test closures auto-promote to the async type so no test churn.
<!-- SECTION:FINAL_SUMMARY:END -->
