---
id: TASK-690
title: Work down the 47 unused declarations Periphery found
status: To Do
assignee: []
created_date: '2026-08-22 22:42'
labels: []
dependencies: []
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
