---
id: TASK-396
title: >-
  Release workflows: Parse Project.swift marketingVersion correctly before tag
  validation
status: To Do
assignee: []
created_date: '2026-06-12 23:34'
labels:
  - audit
  - release
  - ci
  - versioning
dependencies: []
references:
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - Project.swift
  - .github/workflows/version-parity.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DMG and MAS release workflows parse `APP_VERSION` by grepping `MARKETING_VERSION`, which returns the Info.plist placeholder `$(MARKETING_VERSION)` instead of the Tuist `.marketingVersion("...")` value. As a result, real version tags will fail release validation even when Project.swift is correct.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DMG and MAS release workflows extract the same Project.swift version value as the version-parity workflow.
- [ ] #2 A local shell smoke check demonstrates the release parser returns the numeric marketing version, not `$(MARKETING_VERSION)`.
- [ ] #3 Release tag validation passes when tag, Project.swift marketingVersion, and extension manifest version match.
- [ ] #4 Release tag validation fails with a clear message when any of the three versions differ.
<!-- AC:END -->
