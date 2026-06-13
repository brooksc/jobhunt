---
id: TASK-414
title: >-
  Repository hygiene: Normalize test source paths to one case across Git,
  Project.swift, CI, and docs
status: To Do
assignee: []
created_date: '2026-06-13 03:21'
labels:
  - audit
  - repo-hygiene
  - tests
  - developer-workflow
dependencies: []
references:
  - Project.swift
  - tests
  - README.md
  - CONTRIBUTING.md
  - .github/workflows/swift-build.yml
  - scripts
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Git tracks lowercase `tests/`, while Project.swift and docs reference a mix of `tests/` and `Tests/`. This relies on case-insensitive macOS behavior and can fail or drift on case-sensitive filesystems or clean CI variants. Choose one canonical path and update project configuration, CI, scripts, and docs consistently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Project.swift references one canonical test directory casing for all test targets.
- [ ] #2 README, CONTRIBUTING, docs, scripts, and CI reference the same casing.
- [ ] #3 A clean checkout on a case-sensitive filesystem can generate the project and enumerate tests.
- [ ] #4 A guard or CI check prevents reintroducing mixed-case test paths.
<!-- AC:END -->
