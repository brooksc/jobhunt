---
id: TASK-139
title: 'Release: Make version bump script Swift/Tuist-native'
status: To Do
assignee: []
created_date: '2026-06-11 03:40'
labels:
  - release
  - versioning
  - developer-experience
dependencies: []
references:
  - scripts/bump-version.sh
  - README.md
  - Project.swift
  - extension/manifest.json
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README documents `./scripts/bump-version.sh patch|minor|major`, but the script currently requires package.json for semver bump mode even though this Swift/Tuist tree has no package.json. Make versioning work for the current project shape.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `scripts/bump-version.sh patch|minor|major` works when package.json is absent by reading/updating Project.swift marketingVersion.
- [ ] #2 Explicit version mode and semver bump mode both update Project.swift and extension/manifest.json when present.
- [ ] #3 The script does not auto-commit unless that behavior is intentionally documented and desired.
- [ ] #4 README versioning instructions match the implemented script behavior.
<!-- AC:END -->
