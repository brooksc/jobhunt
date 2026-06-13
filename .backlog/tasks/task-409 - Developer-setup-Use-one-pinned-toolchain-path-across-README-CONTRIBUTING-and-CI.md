---
id: TASK-409
title: >-
  Developer setup: Use one pinned toolchain path across README, CONTRIBUTING,
  and CI
status: To Do
assignee: []
created_date: '2026-06-13 01:59'
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
- [ ] #1 README and CONTRIBUTING both describe the same pinned tool installation path.
- [ ] #2 Docs mention all tools pinned in `.mise.toml`, not only Tuist where SwiftLint/SwiftFormat are required for CI.
- [ ] #3 Setup instructions avoid unpinned Tuist installation for normal development.
- [ ] #4 A first-time contributor can follow one documented path from clone to generated project.
<!-- AC:END -->
