---
id: TASK-381
title: 'LLM provider factory: Build providers from a Sendable settings snapshot'
status: To Do
assignee: []
created_date: '2026-06-12 22:55'
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
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QueueActor snapshots extraction settings on the main actor, but providerFactory captures SettingsStore directly and QueueActor calls it from the queue actor, crossing actor/thread boundaries with a non-Sendable observable settings object.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Provider construction uses a Sendable settings/API-key snapshot or is explicitly isolated to the main actor.
- [ ] #2 Queue processing no longer reads live SettingsStore directly from QueueActor isolation.
- [ ] #3 Tests or compiler checks cover provider selection from the snapshot.
<!-- AC:END -->
