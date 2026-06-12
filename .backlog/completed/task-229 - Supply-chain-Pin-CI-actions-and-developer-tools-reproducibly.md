---
id: TASK-229
title: 'Supply chain: Pin CI actions and developer tools reproducibly'
status: Done
assignee: []
created_date: '2026-06-12 01:42'
updated_date: '2026-06-12 02:16'
labels:
  - supply-chain
  - ci
  - tooling
dependencies: []
references:
  - .github/workflows/swift-build.yml
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - .github/workflows/llm-eval.yml
  - .mise.toml
  - CONTRIBUTING.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI uses moving GitHub Action major tags and installs latest swiftlint/swiftformat via Homebrew. Pin action SHAs and pin tool versions through a reproducible mechanism such as mise or a Brewfile.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GitHub Actions are pinned to immutable SHAs or an approved dependency policy is documented.
- [ ] #2 SwiftLint and SwiftFormat versions are pinned and installed reproducibly in CI.
- [ ] #3 Contributor setup documentation matches the CI tool versions.
- [ ] #4 A dependency update process is documented so pins can be refreshed deliberately.
<!-- AC:END -->
