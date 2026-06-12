---
id: TASK-399
title: >-
  Release workflows: Use pinned mise-managed tools and fail on dependency
  install errors
status: To Do
assignee: []
created_date: '2026-06-12 23:34'
labels:
  - audit
  - release
  - ci
  - tooling
  - supply-chain
dependencies: []
references:
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - .github/workflows/swift-build.yml
  - .mise.toml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Normal CI uses `.mise.toml` to pin Tuist, SwiftLint, and SwiftFormat, but release workflows curl-install Tuist and run `tuist install || true`. Release builds should use the same pinned toolchain as CI and fail when dependency installation fails.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DMG and MAS release workflows install tools through the pinned mise configuration or an equivalently pinned mechanism.
- [ ] #2 Release workflows no longer mask `tuist install` failures.
- [ ] #3 Release and normal CI use the same Tuist version unless an intentional difference is documented.
- [ ] #4 Workflow comments reflect the actual tool installation path.
<!-- AC:END -->
