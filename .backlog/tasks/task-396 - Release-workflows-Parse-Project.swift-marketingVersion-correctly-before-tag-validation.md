---
id: TASK-396
title: >-
  Release workflows: Parse Project.swift marketingVersion correctly before tag
  validation
status: Done
assignee: []
created_date: '2026-06-12 23:34'
updated_date: '2026-06-15 05:52'
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
modified_files:
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DMG and MAS release workflows parse `APP_VERSION` by grepping `MARKETING_VERSION`, which returns the Info.plist placeholder `$(MARKETING_VERSION)` instead of the Tuist `.marketingVersion("...")` value. As a result, real version tags will fail release validation even when Project.swift is correct.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DMG and MAS release workflows extract the same Project.swift version value as the version-parity workflow.
- [x] #2 A local shell smoke check demonstrates the release parser returns the numeric marketing version, not `$(MARKETING_VERSION)`.
- [x] #3 Release tag validation passes when tag, Project.swift marketingVersion, and extension manifest version match.
- [x] #4 Release tag validation fails with a clear message when any of the three versions differ.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
release-dmg.yml and release-mas.yml grepped MARKETING_VERSION, which matches the Info.plist line `"$(MARKETING_VERSION)"` and the sed then extracted that literal placeholder rather than the real version, so valid tags failed release validation. Switched both to the exact parser version-parity.yml uses: `grep -o '\.marketingVersion("[0-9.]*")' Project.swift | grep -o '"[0-9.]*"' | tr -d '"'` (AC#1). Smoke check demonstrated locally: broken parser returns `$(MARKETING_VERSION)`, fixed parser returns `1.0.0` (AC#2). The surrounding tag/app/extension equality checks (with clear ERROR messages) now operate on the real numeric version, so validation passes when all three match and fails clearly otherwise (AC#3/#4).
<!-- SECTION:FINAL_SUMMARY:END -->
