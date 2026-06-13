---
id: TASK-412
title: 'Repository hygiene: Remove or formalize duplicate Tests and tests source trees'
status: To Do
assignee: []
created_date: '2026-06-13 02:05'
labels:
  - audit
  - developer-workflow
  - repo-hygiene
  - tests
dependencies: []
references:
  - Project.swift
  - Tests
  - tests
  - .github/workflows/swift-build.yml
  - README.md
  - CONTRIBUTING.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Both `Tests/` and `tests/` contain duplicate Swift test sources. Project.swift builds from `Tests/**`, CI formats `Tests`, and docs link lowercase paths in places. This creates a high-risk edit drift trap, especially on case-sensitive filesystems and in review diffs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 There is one canonical Swift test source tree, or the duplicate tree is generated/formalized with an explicit sync check.
- [ ] #2 Project.swift, CI, lint/format commands, and docs all reference the canonical path consistently.
- [ ] #3 Case-sensitive filesystem behavior is considered and documented if both paths remain.
- [ ] #4 A guard prevents future divergence between duplicated test trees if both must remain temporarily.
<!-- AC:END -->
