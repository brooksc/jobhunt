---
id: TASK-529
title: >-
  Concurrency: make AppServices actor isolation explicit instead of relying on
  @unchecked Sendable
status: To Do
assignee: []
created_date: '2026-06-19 04:45'
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
- [ ] #1 `AppServices` mutable UI state is protected by explicit `@MainActor` isolation or an equivalent narrowly-scoped design.
- [ ] #2 QueueActor closures continue to access `SettingsStore` only through main-actor snapshots.
- [ ] #3 `runtimeTasks` is mutated only on its documented actor/executor.
- [ ] #4 The service graph still builds without introducing runtime side effects during initialization.
- [ ] #5 Focused tests or compile-time annotations cover startup/shutdown and settings snapshot paths without relying on broad `@unchecked Sendable`.
<!-- AC:END -->
