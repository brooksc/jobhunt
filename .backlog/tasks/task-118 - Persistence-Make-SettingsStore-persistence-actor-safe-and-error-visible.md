---
id: TASK-118
title: 'Persistence: Make SettingsStore persistence actor-safe and error-visible'
status: To Do
assignee: []
created_date: '2026-06-11 02:46'
labels:
  - persistence
  - settings
  - swiftdata
  - concurrency
dependencies: []
references:
  - core/Settings/SettingsStore.swift
  - app/Shell/AppServices.swift
  - core/LLM/QueueActor.swift
  - tests/CoreTests/SettingsStoreTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`SettingsStore` keeps its own `ModelContext`, in-memory cache, and `try?` save path while runtime services use `BackgroundStore`. `QueueActor` also holds `SettingsStore` through a `nonisolated(unsafe)` property. Make settings persistence a single actor-safe service path so queue pause state, provider settings, availability timestamps, and UI settings do not silently diverge or swallow persistence errors.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings persistence has one authoritative runtime path for reads and writes used by UI and background services
- [ ] #2 Settings writes that affect runtime behavior no longer silently swallow save failures
- [ ] #3 `QueueActor` no longer requires unsafe access to mutable `SettingsStore` state, or the remaining unsafe access is narrowly justified and tested
- [ ] #4 Existing keychain behavior for API keys remains unchanged and API keys are not persisted to SwiftData
- [ ] #5 Tests cover settings mutation visibility between UI-facing settings and background queue/provider code
<!-- AC:END -->
