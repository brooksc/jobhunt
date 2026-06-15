---
id: TASK-414
title: >-
  Repository hygiene: Normalize test source paths to one case across Git,
  Project.swift, CI, and docs
status: Done
assignee: []
created_date: '2026-06-13 03:21'
updated_date: '2026-06-15 06:06'
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
modified_files:
  - Project.swift
  - .github/workflows/swift-build.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Git tracks lowercase `tests/`, while Project.swift and docs reference a mix of `tests/` and `Tests/`. This relies on case-insensitive macOS behavior and can fail or drift on case-sensitive filesystems or clean CI variants. Choose one canonical path and update project configuration, CI, scripts, and docs consistently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Project.swift references one canonical test directory casing for all test targets.
- [x] #2 README, CONTRIBUTING, docs, scripts, and CI reference the same casing.
- [x] #3 A clean checkout on a case-sensitive filesystem can generate the project and enumerate tests.
- [x] #4 A guard or CI check prevents reintroducing mixed-case test paths.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Git tracks only lowercase tests/ (55 files). Project.swift mixed casing: tests/CoreTests vs Tests/{ServerTests,MCPTests,AppUITests,LLMEval}. Normalized all five test-source globs to lowercase tests/ (AC#1) — those capital-T globs only matched on case-insensitive macOS and would fail to enumerate on a case-sensitive checkout (AC#3 now satisfied: globs match git's actual lowercase paths). README/CONTRIBUTING use lowercase tests/; swift-build.yml swiftformat targets `tests`; the only capital Tests in scripts (screenshot-tests.sh `-only-testing AppUITests/ScreenshotTests`) is a test target/class identifier, not a path (AC#2). Added a swift-build.yml "Guard against mixed-case test paths" step that fails the build if a capital-T "Tests/" path reappears in Project.swift (AC#4). Regenerated; fast gate enumerates Core/Server/MCP correctly.
<!-- SECTION:FINAL_SUMMARY:END -->
