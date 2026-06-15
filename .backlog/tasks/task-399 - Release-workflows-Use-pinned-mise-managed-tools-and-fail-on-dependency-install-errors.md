---
id: TASK-399
title: >-
  Release workflows: Use pinned mise-managed tools and fail on dependency
  install errors
status: Done
assignee: []
created_date: '2026-06-12 23:34'
updated_date: '2026-06-15 06:08'
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
modified_files:
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Normal CI uses `.mise.toml` to pin Tuist, SwiftLint, and SwiftFormat, but release workflows curl-install Tuist and run `tuist install || true`. Release builds should use the same pinned toolchain as CI and fail when dependency installation fails.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DMG and MAS release workflows install tools through the pinned mise configuration or an equivalently pinned mechanism.
- [x] #2 Release workflows no longer mask `tuist install` failures.
- [x] #3 Release and normal CI use the same Tuist version unless an intentional difference is documented.
- [x] #4 Workflow comments reflect the actual tool installation path.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Both release workflows now install tools via mise using the pinned .mise.toml (Tuist 4.196.1) — the exact same steps as swift-build.yml — instead of curl-installing the latest Tuist (AC#1, AC#3). Removed `tuist install || true`, so a dependency/tool install failure now fails the job instead of being masked (AC#2); dropped the separate tuist-install step since swift-build.yml builds without it (no Tuist-managed deps). Step names/comments now describe the mise path and reference TASK-399 (AC#4). YAML validated with yaml.safe_load. Can't execute the GH Actions runner locally, but the change mirrors the already-green swift-build.yml toolchain setup.
<!-- SECTION:FINAL_SUMMARY:END -->
