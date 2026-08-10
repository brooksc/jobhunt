---
id: TASK-570
title: >-
  Wire remaining static-analysis gates into CI (Periphery, warnings, analyze,
  ShellCheck, a11y)
status: To Do
assignee: []
created_date: '2026-06-20 04:24'
updated_date: '2026-08-10 00:10'
labels:
  - ci
  - static-analysis
  - tech-debt
dependencies: []
modified_files:
  - .github/workflows/shellcheck.yml
  - .github/workflows/swift-build.yml
  - scripts/check-warnings.sh
  - scripts/run-ui-tests-in-vm.sh
  - .warning-baseline
priority: low
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up to TASK-545 (which restored the green `swiftlint lint --strict` gate). These additional
gates were scoped into 545 but are independent CI hardening — split out so 545 could close.

- **Periphery** dead-code scan: an early run surfaced ~274 findings incl. real dead code
  (`PlatformIntegration.updateDockBadge`, `FitPillView`) mixed with `@Environment`/redundant-public
  false positives. Needs retain rules / a baseline, then a CI step. Config had an invalid `targets`
  key to fix.
- **Compiler-warnings gate**: fail CI on new warnings (strict concurrency). Only 1 real warning at
  last check (a `SettingsTab` data race, since fixed) — wire a gate so new ones don't accrue.
- **`swiftlint analyze`** (compiler-backed rules).
- **ShellCheck**: installed locally (0.10.0); add an install + lint step for `scripts/*.sh`
  (2 warnings + 11 info at last run, no errors). A standalone `gitleaks.yml` already exists as the
  model for a small dedicated workflow.
- **XCUITest `performAccessibilityAudit`** in AppUITests.

Gitleaks + Dependabot are already wired. None of these is a release blocker.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ShellCheck runs in CI over scripts/*.sh
- [x] #2 A compiler-warning gate prevents new warnings accruing
- [ ] #3 Periphery dead-code scan runs in CI
- [ ] #4 swiftlint analyze runs in CI
- [ ] #5 AppUITests runs performAccessibilityAudit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**2026-08-09 — two of five gates wired; three parked with reasons.**

**ShellCheck (done).** New `shellcheck.yml`, gating at `--severity=warning`. Deliberately not at `note`: the scripts carry ~58 style notes, mostly SC2086 word-splitting on paths we control, and failing on those means either 58 edits to release-critical scripts or a wall of inline disables — neither buys correctness. The two genuine warnings the task mentions (unused `GUEST_SRC` and `TART_PID` in the VM runner) were removed rather than suppressed. Zero warnings, zero errors now.

**Compiler warnings (done, as a ratchet).** The task's "only 1 real warning at last check" is stale — a clean build emits **58 distinct warnings**, of which **49 are `KeyPath<Model, …> does not conform to Sendable`** raised by SwiftData's own `#Predicate`/`SortDescriptor` machinery under strict concurrency. Those aren't ours to fix and suppressing them wholesale would hide the nine that are. So `scripts/check-warnings.sh` counts distinct warnings and fails when the count exceeds `.warning-baseline` (58). New warnings can't accrue; changing the number is a deliberate, visible commit. The nine non-Sendable warnings are worth their own task — an unused `now` in DemoSeeder, an unused `try?` in QueueActor, a `var` that should be `let`, a weak/strong capture mismatch in JobhuntServer, a missing Combine import in DashboardView, an actor-isolation warning in OnboardingView, and a missing AccentColor asset.

**Periphery (parked).** Needs a curated retain-rule set or a baseline before it can gate: the earlier run's ~274 findings mix real dead code with `@Environment`-property and redundant-`public` false positives, and a scan that's mostly noise gets ignored or disabled within a week. Landing it properly is its own task, not a step in this one.

**`swiftlint analyze` (parked).** Requires a full compiler log per run, roughly doubling CI build time, and the compiler-backed rule set overlaps heavily with what `--strict` already enforces. Not worth the wall-clock until there's a specific rule we want from it.

**Accessibility audit (parked).** `performAccessibilityAudit` lives in AppUITests, which needs a graphical session. That's the same constraint that parks the other UI-verification work in this sweep.
<!-- SECTION:NOTES:END -->
