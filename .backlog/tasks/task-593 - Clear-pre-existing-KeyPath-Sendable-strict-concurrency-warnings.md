---
id: TASK-593
title: Clear pre-existing KeyPath-Sendable strict-concurrency warnings
status: To Do
assignee: []
created_date: '2026-07-04 02:40'
labels:
  - concurrency
  - warnings
  - tech-debt
  - tests
dependencies: []
references:
  - tests/CoreTests/FixtureTests.swift
  - tools/migrator/SQLiteHelpers.swift
  - core/Services/BackgroundStore.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A clean rebuild surfaces ~50 pre-existing strict-concurrency warnings (SWIFT_STRICT_CONCURRENCY=complete; errors in Swift 6 language mode). These are separate from the BackgroundStore.fetch `@Model` warning already fixed (commit 7aaa908).

Breakdown observed in a full CoreTests/ServerTests/MCPTests build:
- ~44 `type 'KeyPath<Model, Field>' does not conform to the 'Sendable' protocol` — from `SortDescriptor(\.field)` and `#Predicate` keypaths crossing the actor boundary (mostly test code, e.g. `FetchDescriptor(sortBy: [SortDescriptor(\.jobNumber)])`). Types seen: Job, LLMRequest, Resume, Capture, JobFitScore, DuplicateDecision, Setting.
- A few miscellaneous: `static property 'zero' ... JobStatusSummary`; test-mock nonisolated global statics (requestHandler/handlers/capturedRequests); `captured var 'paused'` mutation in a concurrently-executing test closure; `ISO8601DateFormatter` non-Sendable `let`s in tools/migrator/SQLiteHelpers.swift:71,77 (isoFrac/isoBasic).
- 2 harmless Xcode build notes ("Metadata extraction skipped. No AppIntents.framework dependency found") — not real warnings.

Why it matters: a wall of ~50 warnings hides genuinely new warnings and blocks eventually moving to the Swift 6 language mode.

Suggested approach: KeyPath<Model,Field> Sendability is the bulk — investigate whether hoisting SortDescriptors/predicates or a small helper resolves them, or accept until the Swift 6 migration. Fix the low-risk ones (migrator ISO8601DateFormatter statics → make them `static let` on a Sendable wrapper or compute locally; test-mock statics → actor/@MainActor isolation or nonisolated(unsafe) with justification). Do NOT do a broad risky refactor of the query sites without measuring.
<!-- SECTION:DESCRIPTION:END -->
