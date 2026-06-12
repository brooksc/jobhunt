---
id: TASK-342
title: 'Release workflows: Verify tag version matches app and extension versions'
status: To Do
assignee: []
created_date: '2026-06-12 20:36'
labels:
  - audit
  - release
  - ci
  - versioning
dependencies: []
references:
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - .github/workflows/version-parity.yml
  - Project.swift
  - extension/manifest.json
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Release workflows run on any v* tag, while version parity runs only on branch pushes/PRs and checks app vs extension version, not tag vs product version. A mistagged release can ship artifacts whose internal version does not match the GitHub tag.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DMG and MAS release jobs fail when github.ref_name does not match Project.swift MARKETING_VERSION.
- [ ] #2 Release jobs also verify extension manifest version matches the app version before packaging/upload.
- [ ] #3 The check handles tags with a leading v, such as v1.2.3.
<!-- AC:END -->
