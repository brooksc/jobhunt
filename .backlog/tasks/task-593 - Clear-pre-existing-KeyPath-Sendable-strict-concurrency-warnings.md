---
id: TASK-593
title: Clear pre-existing KeyPath-Sendable strict-concurrency warnings
status: Done
assignee: []
created_date: '2026-07-04 02:40'
updated_date: '2026-08-09 20:04'
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
ordinal: 42000
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

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The low-risk non-KeyPath warnings named in the report are cleared: migrator ISO8601DateFormatter statics and JobStatusSummary.zero
- [x] #2 The build still succeeds and the fast gate passes after the change
- [ ] #3 not done (deliberate): the KeyPath<Model, Field> warnings remain — they need the Swift 6 language-mode migration, and the report itself says not to refactor the query sites without measuring. Measured: 9 unique sites, all from SortDescriptor/#Predicate crossing an actor boundary.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
**Measured first, since the report's numbers were stale.** A clean build gives **60 unique** warnings, not ~50 — and the 432 raw lines are the same warnings repeated across targets. Of the specific low-risk items the report names, most were already fixed by other work; three remained.

**Fixed (60 → 57):**

- `tools/migrator/SQLiteHelpers.swift` — `isoFrac` / `isoBasic` were shared `ISO8601DateFormatter` globals. That class has mutable `formatOptions`, so a shared instance isn't `Sendable`. Replaced with a `makeISO(fractionalSeconds:)` factory called per parse, which removes the shared state rather than asserting it away with `nonisolated(unsafe)`. The migrator is a one-shot CLI over a few thousand rows, so a formatter per parse isn't worth measuring.
- `core/Services/JobStatusSummary.swift` — `zero` is a static let of a non-`Sendable` struct. Marked `@unchecked Sendable`: everything it holds is a value type, but `funnelCounts` is a tuple array, which blocks automatic inference.

**Deliberately not done — the KeyPath bulk.** Nine unique sites, all `SortDescriptor(\.field)` / `#Predicate` keypaths crossing an actor boundary. `KeyPath` gains conditional `Sendable` in the Swift 6 language mode; there is no local fix that isn't either a wrapper around every query site or `@preconcurrency`/`@unchecked` suppression. The report explicitly says not to refactor the query sites without measuring, and doing it here would be a broad change to every fetch in the codebase for no behaviour gain. It belongs with the Swift 6 migration, and the third criterion records that rather than quietly leaving it unchecked.

This task was On Hold; it qualified as WORK under the run's rules because the remaining part is build-verifiable and the deferred part is now explicit.
<!-- SECTION:FINAL_SUMMARY:END -->
