---
id: TASK-703
title: >-
  29 call sites still read live @Model rows off the store actor — add a
  mechanical check
status: To Do
assignee: []
created_date: '2026-08-31 19:29'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-08-31 test-coverage audit (`scratchpad/audit-tests.md`, P0 #1). Its top recommendation is not a test — it's a check, because this defect class **cannot be unit-tested**.

The bug: a live SwiftData `@Model` row returned from `BackgroundStore` (a `@ModelActor`) and then read or mutated outside that actor. Commit `df3df01d` fixed one instance after it **corrupted the heap**. [[TASK-692]]'s Wave A fixed six more (`DiscoveryScheduler`, `MarketSweeper`, `SiteService`).

The audit reports **29 call sites still doing it**, including `core/Services/JobService.swift:631` and `:663`, and `server/swift/MCPBridgeRoutes.swift:605`. Verify that list before acting — some may be on-actor and misidentified.

**Why a script and not tests.** The failure is a data race: it depends on timing, needs concurrent load to reproduce, and a passing test proves nothing. Swift 6's `sending` diagnostics catch the cases that cross an explicit isolation boundary in the signature, but not every shape — Wave A had to find several by reading. A grep-level check that flags a `BackgroundStore` method returning a `@Model` type, or a `@Model` used after being handed to the actor, catches the pattern at review time, where it's free.

Proposed: `scripts/check-model-isolation.sh` plus a CI step, in the same register as `check-warnings.sh` and the new `check-docs.sh` — a ratchet with a baseline, so the existing 29 don't block the build but no new one can be added.

The correct fix at each site is the established one: build a `Sendable` snapshot struct inside the actor and return that. `BackgroundStore.staleAvailabilityInputs` / `AvailabilityChecker.JobInput` (`core/Services/BackgroundStore.swift:1199-1264`) and the new `DueSource` / `MarketSweepSnapshot` from Wave A are the models to copy.

Related: [[TASK-695]] is the same class caught before it happened — `insertSavedSearch` is safe only by accident of who calls it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The 29 reported call sites are verified; false positives removed and the real list recorded
- [ ] #2 scripts/check-model-isolation.sh flags a @Model crossing the BackgroundStore actor boundary
- [ ] #3 It runs in CI as a ratchet with a baseline, so existing sites don't block the build but new ones fail
- [ ] #4 The highest-traffic real sites are converted to Sendable snapshots, following DueSource/JobInput
<!-- AC:END -->
