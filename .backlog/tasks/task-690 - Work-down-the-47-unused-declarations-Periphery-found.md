---
id: TASK-690
title: Work down the 47 unused declarations Periphery found
status: Done
assignee: []
created_date: '2026-08-22 22:42'
updated_date: '2026-08-22 23:00'
labels:
  - tech-debt
  - static-analysis
dependencies: []
priority: low
type: chore
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The dead-code scan now gates at a baseline of 47 (TASK-570 #3, `.periphery-baseline`). Those 47 are real candidates, not noise — the two analyses that produced noise here (redundant-public on framework API, assign-only on SwiftUI property wrappers) are disabled in `.periphery.yml` with the reasoning, which took the raw 431 down to 47.

`./scripts/check-periphery.sh --list` prints the current set. From the 2026-08-22 scan, the clearly-dead end of it:

- `app/Views/Components/CompanyCell.swift` — whole struct
- `app/Views/Components/FitRingView.swift` — `FitPillView`
- `app/Views/Components/StarRating.swift` — whole struct
- `app/Views/Detail/JobDetailPlaceholder.swift` — whole struct
- `app/Platform/PlatformIntegration.swift` — `updateDockBadge(count:)`
- `core/LLM/CostEstimator.swift` — the OpenRouter pricing fetch and its three supporting types
- `app/Views/Detail/JobDetailView.swift` — six unused `@State`/`@Environment` properties

Needing judgement rather than deletion:

- `tests/CoreTests/DuplicateDetectorTests.swift:1058` `testRawHashDoesNotTrapOnHugeJSONLDNumber` is reported unused. XCTest invokes test methods by runtime lookup, so Periphery is usually taught to retain them — worth finding out why this one isn't, because if it genuinely isn't running, that's a silently-lost regression test, not dead code.
- `KeychainStore.delete(_:)` and `MCPTokenManager.delete()` are teardown paths that may only be exercised by hand. Removing a way to delete a secret is not obviously an improvement.
- `Router` label properties and `QualityIssue.severity` may be read by SwiftUI or by code Periphery can't see through.

Lower `.periphery-baseline` with each pass — that number is what stops the debt growing back. Anything Periphery is wrong about should get an explicit retain rule in `.periphery.yml` with a reason, rather than a raised baseline.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every clearly-dead declaration is deleted, along with anything its removal orphans
- [x] #2 The reported-unused test method is explained: either it genuinely doesn't run (and is fixed) or Periphery is retaining it wrongly (and the config says so)
- [x] #3 Anything Periphery is wrong about carries an explicit retain rule with a reason, not a raised baseline
- [x] #4 .periphery-baseline is lowered to the new count and the scan passes
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
46 → 0. `.periphery-baseline` is now 0, so the next unused declaration fails the scan outright rather than being absorbed.

**Deleted (#1).** Most were superseded rather than mistaken, which is what made them safe:
- `FitPillView`, `CompanyCell`, `StarRating`, `JobDetailPlaceholder` — nothing has rendered them since the Jobs list moved to `FitRingView`.
- `CostEstimator`'s live OpenRouter pricing and its three supporting types — a port of the old Node server's `/api/llm-pricing` that no Swift caller ever made.
- `BackgroundStore.deleteFitScores(forResumeID:)` — both paths it existed for are gone: editing a résumé now marks scores stale rather than deleting them (deliberate, so the user decides whether to re-spend), and resume deletion cascades through the model relationship.
- `DuplicateDetector.titleGroupKey` — replaced by `titleTokens`/`titlesAreSimilar` in TASK-620.
- `updateDockBadge`, `JobService.enqueueLLM`, `QualityIssue.severity`, `ReferralSummary.needsAction`, `recipientKey`, `requirementShare`, `JobFilterRules.label`, `Exclusions.none`, `JobhuntServerError`, `structuredDataJSONField`, `JobsFilterState.init(from:)`, `QueueActor.activeCounts`, Router's three display helpers, nine stranded `@State`/`@Environment` properties, and two unused UI-test helpers.
- A stale doc comment in `FitBand` referring to the deleted pill was corrected rather than left lying.

**#2 — the reported-unused test was real.** `testRawHashDoesNotTrapOnHugeJSONLDNumber` sat inside a `private extension JobSnapshot` at the foot of DuplicateDetectorTests, not the XCTestCase, so XCTest never ran it. It covers a trap on an integer-valued Double outside Int range from attacker-controlled JSON-LD — a crash on capture. Moved into the class in the TASK-570 commit; runs and passes.

**#3 — kept, with reasons in the code.** `KeychainStore.delete` and `MCPTokenManager.delete` carry `// periphery:ignore`: nothing calls either today, but a credential store that can only ever add is the wrong shape, and the protocol requirement must exist for a test double to conform. Tuist's `Derived/` is excluded from the report — generated asset accessors are the generator's business, and the file isn't ours to edit.

**#4** Scan clean at 0. Full gate green: CoreTests/ServerTests/MCPTests pass, coverage above floor, 141 extension tests, SwiftLint/SwiftFormat clean.
<!-- SECTION:FINAL_SUMMARY:END -->
