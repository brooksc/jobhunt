---
id: TASK-354
title: 'CI tooling: Pin SwiftLint and SwiftFormat versions'
status: Done
assignee: []
created_date: '2026-06-12 20:43'
updated_date: '2026-06-12 21:53'
labels:
  - audit
  - supply-chain
  - ci
  - tooling
dependencies: []
references:
  - .github/workflows/swift-build.yml
  - .mise.toml
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
swift-build.yml installs swiftlint and swiftformat through Homebrew without pinning versions. Lint/format results can drift when Homebrew updates even when the source code has not changed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SwiftLint and SwiftFormat versions are pinned through mise, Homebrew bundle, or another reproducible mechanism.
- [ ] #2 CI and local development documentation use the same pinned versions.
- [ ] #3 Version bumps are intentional code-reviewable changes.
<!-- AC:END -->
