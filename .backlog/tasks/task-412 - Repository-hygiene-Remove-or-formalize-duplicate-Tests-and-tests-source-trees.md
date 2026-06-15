---
id: TASK-412
title: 'Repository hygiene: Remove or formalize duplicate Tests and tests source trees'
status: Done
assignee: []
created_date: '2026-06-13 02:05'
updated_date: '2026-06-15 06:06'
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
modified_files:
  - Project.swift
  - .github/workflows/swift-build.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Both `Tests/` and `tests/` contain duplicate Swift test sources. Project.swift builds from `Tests/**`, CI formats `Tests`, and docs link lowercase paths in places. This creates a high-risk edit drift trap, especially on case-sensitive filesystems and in review diffs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 There is one canonical Swift test source tree, or the duplicate tree is generated/formalized with an explicit sync check.
- [x] #2 Project.swift, CI, lint/format commands, and docs all reference the canonical path consistently.
- [x] #3 Case-sensitive filesystem behavior is considered and documented if both paths remain.
- [x] #4 A guard prevents future divergence between duplicated test trees if both must remain temporarily.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Investigated: the "duplicate Tests/ and tests/ trees" premise is incorrect — git tracks ONLY lowercase tests/ (55 files), and `git ls-files | grep '^Tests/'` returns nothing. There was never a second tree; the confusion was Project.swift's mixed-case globs resolving to the same dir on case-insensitive macOS. Resolved together with TASK-414: normalized all Project.swift test globs to the single canonical lowercase tests/ (AC#1), aligned by CI/lint/docs which already used lowercase (AC#2), documented the case-sensitivity rationale in the guard comment (AC#3), and added a swift-build.yml guard preventing reintroduction of a capital-T path (AC#4). No tree to delete/sync since only one exists.
<!-- SECTION:FINAL_SUMMARY:END -->
