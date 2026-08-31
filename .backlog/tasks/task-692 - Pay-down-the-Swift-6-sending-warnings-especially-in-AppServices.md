---
id: TASK-692
title: 'Pay down the Swift 6 ''sending'' warnings, especially in AppServices'
status: To Do
assignee: []
created_date: '2026-08-31 17:41'
labels: []
dependencies: []
references:
  - scripts/check-warnings.sh
  - .warning-baseline
  - app/Shell/AppServices.swift
  - core/Services/AvailabilityChecker.swift
priority: high
type: chore
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The compiler-warning baseline was set at 58 on 2026-08-09 and never revisited across 198 commits, during which the whole discovery feature landed. A clean build now emits 69 distinct warnings, so the ratchet has been failing "Swift Build" for weeks and the check stopped being read.

Three trivial ones were fixed when the ratchet was unblocked (an unused `withBudget` result, a `var` never mutated, an unused local). The baseline was then raised to 69 deliberately, which is what `scripts/check-warnings.sh` sanctions — but that absorbs roughly eight real warnings rather than fixing them.

**Why this is higher priority than a normal warning cleanup.** The bulk of the excess is `sending 'x' risks causing data races; this is an error in the Swift 6 language mode`, concentrated in AppServices (19 warnings). That is the *same class* of defect as the crash fixed in df3df01d, where live SwiftData `@Model` rows were read off the store actor and corrupted the heap on launch. The compiler was already saying so; nobody was reading it because the check was permanently red.

These are also errors under the Swift 6 language mode proper, so they block that migration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `./scripts/check-warnings.sh` passes with a baseline meaningfully below 69, and the new number is committed
- [ ] #2 The `sending`/actor-isolation warnings in app/Shell/AppServices.swift are resolved or each one has a comment explaining why it is safe and unavoidable
- [ ] #3 No `@Model` value crosses an isolation boundary anywhere the compiler flags — the pattern from df3df01d (a Sendable snapshot built on the owning isolation) is applied wherever it fits
- [ ] #4 The remaining baseline consists only of warnings emitted by Apple's own SwiftData KeyPath/Predicate machinery, which the script's header already documents as not ours to fix
<!-- AC:END -->
