---
id: TASK-545
title: Get SwiftLint --strict green + finish static-analysis gates
status: To Do
assignee: []
created_date: '2026-06-19 07:49'
labels:
  - tech-debt
  - ci
  - static-analysis
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Background

CI's `swift-build.yml` runs `swiftlint lint --strict`, which **turns warnings into errors**. It has been **failing on every run since ~2026-06-08** (the Swift rewrite), so the SwiftLint gate has not actually been enforced. Discovered while auditing static analysis for release.

### Progress already landed (do NOT redo)
- `swiftlint --fix` + `swiftformat` cleared the mechanical rules: **395 → 133** violations (line_length 166→20, colon/trailing_comma/statement_position/vertical_whitespace → 0). Build + fast gate verified green. (Also fixed a swiftformat `hoistAwait` regression that moved `await` out of `XCTUnwrap`'s non-async autoclosure in `UniquenessInvariantTests`.)
- gitleaks (standalone workflow + `.gitleaks.toml`, scan clean) and Dependabot are committed and green.

## Remaining 133 violations (postponed: higher-risk / lower-value before release)

**Localized (65 ≈ 49%) — genuinely useful, do these:**
- `force_unwrapping` ×23 — replace `x!` with safe unwraps / `XCTUnwrap` (real robustness win; ~half in `OpenRouterRotationTests`)
- `line_length` ×20 — split long lines (several are 300+ char test-data literals in `ExtractionEngineTests`)
- misc ×22 — large_tuple ×3, nesting ×5, function_parameter_count ×4, switch_case_alignment ×2, orphaned_doc_comment ×2, optional_data_string_conversion ×3, statement_position ×1, superfluous_disable_command ×1, static_over_final_class ×1

**Structural (68 ≈ 51%) — the heavy churn:**
- `file_length` ×17, `type_body_length` ×17, `function_body_length` ×17 — splitting files/types/functions
- `cyclomatic_complexity` ×17 — reduce branching (`QueueActor`, `JobhuntServer`, `GoogleProvider`, `Sidebar`, etc.)

## Recommended approach (avoid pointless churn)

Most `file_length`/`type_body_length` hits are **large test files** (2000-line `JobServiceTests`, 700-line `ExtractionEngineTests`) and **cohesive SwiftUI views** (`JobDetailView`) — long, not "too complex." The thresholds (file 500 / type 300) are aggressive for SwiftUI/tests.

1. Fix all **65 localized** violations properly (the real value).
2. Fix the **genuine** offenders: `cyclomatic_complexity` ×17 and `function_body_length` ×17 (these flag functions worth decomposing) — refactor in core/server/view code.
3. **Relax `file_length` → ~800 / `type_body_length` → ~400** and/or **exclude `tests/` from those two rules**, instead of splitting cohesive files just to hit a line count.
4. Re-run `swiftlint lint --strict; echo $?` → 0, fast gate green, then CI's `swift-build.yml` goes green and the gate is actually enforced again.

## Also fold in (remaining static-analysis gates not yet wired)
- **Periphery** dead-code scan — config had an invalid `targets` key; initial run surfaced ~274 findings incl. real dead code (`PlatformIntegration.updateDockBadge`, `FitPillView`) mixed with `@Environment`/redundant-public false positives. Needs retain rules / a baseline, then a CI step.
- **Compiler-warnings gate** (fail CI on new warnings under strict concurrency).
- **`swiftlint analyze`** (compiler-backed rules).
- **ShellCheck** for `scripts/*.sh` (install + CI step).
- **XCUITest `performAccessibilityAudit`** in AppUITests.

## Acceptance
- `swiftlint lint --strict` exits 0; `swift-build.yml` green.
- No behavior change; fast gate + build still green.
- Decision recorded in `.swiftlint.yml` (threshold relaxation / test exclusion) with a comment.
<!-- SECTION:DESCRIPTION:END -->
