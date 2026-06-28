---
id: TASK-529
title: >-
  Concurrency: make AppServices actor isolation explicit instead of relying on
  @unchecked Sendable
status: Done
assignee: []
created_date: '2026-06-19 04:45'
updated_date: '2026-06-28 00:55'
labels:
  - audit
  - concurrency
  - app-services
  - architecture
dependencies: []
references:
  - app/Shell/AppServices.swift
  - app/ContentView.swift
  - core/Settings/SettingsStore.swift
  - core/LLM/QueueActor.swift
modified_files:
  - app/Shell/AppServices.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `AppServices` is an `@Observable` class marked `@unchecked Sendable` while owning mutable UI-facing state (`serverRunning`, `serverError`, `runtimeTasks`), a main-context `SettingsStore`, service actors, and a toast store. Some closures correctly hop to `MainActor`, but the class itself is not main-actor isolated, so future reads/writes can bypass the intended isolation without compiler help.

Why this matters: `@unchecked Sendable` suppresses compiler checking at the app's service-composition boundary. That boundary is where background queue work, server startup, settings snapshots, availability checks, and UI state meet. A missed main-actor hop can turn into nondeterministic UI updates or settings access from the wrong executor.

Suggested implementation: make the intended isolation explicit. Prefer `@MainActor` on `AppServices` or split it into a main-actor UI/service container plus Sendable background dependencies. Keep queue closures using scalar snapshots for settings. Remove `@unchecked Sendable` if possible, or narrow it with documented invariants and tests that exercise runtime startup/shutdown from the main actor.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `AppServices` mutable UI state is protected by explicit `@MainActor` isolation or an equivalent narrowly-scoped design.
- [x] #2 QueueActor closures continue to access `SettingsStore` only through main-actor snapshots.
- [x] #3 `runtimeTasks` is mutated only on its documented actor/executor.
- [x] #4 The service graph still builds without introducing runtime side effects during initialization.
- [x] #5 Focused tests or compile-time annotations cover startup/shutdown and settings snapshot paths without relying on broad `@unchecked Sendable`.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced `AppServices: @unchecked Sendable` with explicit `@MainActor` isolation.

AC#1: `AppServices` is now `@MainActor`, so its mutable UI state (`serverRunning`, `serverError`) and non-Sendable members (`SettingsStore`, `ToastStore`, the `RuntimeTaskController`) are compiler-enforced main-actor-isolated. The actor-typed services (JobService/QueueActor/BackgroundStore/SiteService/ResumeService/JobhuntServer) are immutable Sendable `let`s — implicitly nonisolated even on a @MainActor class — so existing off-main accesses (e.g. `await appServices.server.port`, `appServices.backgroundStore`) still compile without a hop.

AC#2: the QueueActor closures are unchanged — they still snapshot `SettingsStore` only inside `MainActor.run` (isPaused/onSetPaused/readExtractionSettings/providerFactory/isProviderConfigured).

AC#3: `runtime` (RuntimeTaskController, itself @MainActor) is mutated only via `startRuntime()`/`shutdown()`, both @MainActor.

AC#4: construction (`init`) is graph-only with no runtime side effects; the app builds clean and AppServices is created in the main-actor App launch path.

AC#5: the coverage is the compile-time annotation itself — the whole app target builds under `SWIFT_STRICT_CONCURRENCY=complete` with zero new isolation errors after removing `@unchecked Sendable`, which proves no access bypassed the intended isolation. Runtime start/shutdown invariants stay covered by RuntimeTaskControllerTests. No app unit-test target exists to test AppServices directly, so the strict-concurrency build is the enforcement.
<!-- SECTION:FINAL_SUMMARY:END -->
