---
id: TASK-409
title: >-
  Developer setup: Use one pinned toolchain path across README, CONTRIBUTING,
  and CI
status: Done
assignee: []
created_date: '2026-06-13 01:59'
updated_date: '2026-06-17 04:59'
labels:
  - audit
  - developer-workflow
  - docs
  - tooling
dependencies: []
references:
  - README.md
  - CONTRIBUTING.md
  - .mise.toml
  - .github/workflows/swift-build.yml
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README tells developers to install Tuist via the upstream install curl command, while CONTRIBUTING and normal CI use `.mise.toml` as the pinned tool source. Align setup docs around the pinned toolchain so contributors do not unknowingly generate projects with a different Tuist version.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 README and CONTRIBUTING both describe the same pinned tool installation path.
- [x] #2 Docs mention all tools pinned in `.mise.toml`, not only Tuist where SwiftLint/SwiftFormat are required for CI.
- [x] #3 Setup instructions avoid unpinned Tuist installation for normal development.
- [x] #4 A first-time contributor can follow one documented path from clone to generated project.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Aligned README and CONTRIBUTING on the single pinned `.mise.toml` path (AC#1): README's prerequisites + setup now use `mise install` (not the upstream `install.tuist.io` curl), and CONTRIBUTING's dependency-versions + setup sections use `mise install` (was `mise install tuist`). Both now list all three pinned tools — Tuist 4.196.1, SwiftLint 0.63.3, SwiftFormat 0.61.1 — matching CI (AC#2). The unpinned Tuist install is removed and explicitly warned against (AC#3). A first-time contributor follows one path: install mise → `mise install` → `tuist generate --no-open` (AC#4).
<!-- SECTION:FINAL_SUMMARY:END -->
