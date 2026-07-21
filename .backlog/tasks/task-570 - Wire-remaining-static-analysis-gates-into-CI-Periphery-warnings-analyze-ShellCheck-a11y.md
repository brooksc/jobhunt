---
id: TASK-570
title: >-
  Wire remaining static-analysis gates into CI (Periphery, warnings, analyze,
  ShellCheck, a11y)
status: To Do
assignee: []
created_date: '2026-06-20 04:24'
updated_date: '2026-07-21 22:59'
labels:
  - ci
  - static-analysis
  - tech-debt
dependencies: []
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
