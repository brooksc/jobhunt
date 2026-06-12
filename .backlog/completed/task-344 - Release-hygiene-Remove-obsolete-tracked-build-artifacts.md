---
id: TASK-344
title: 'Release hygiene: Remove obsolete tracked build artifacts'
status: Done
assignee: []
created_date: '2026-06-12 20:36'
updated_date: '2026-06-12 20:51'
labels:
  - audit
  - release
  - repo-hygiene
dependencies: []
references:
  - .gitignore
  - Project.swift
  - build/
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The repository ignores build/, but legacy generated files under build/ are still tracked and appear obsolete now that Tuist uses config/entitlements and app resources. These stale files confuse release ownership and can drift from the actual build configuration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Obsolete tracked build/ files are removed if no current workflow depends on them.
- [ ] #2 Release inputs live under source-owned paths such as config/entitlements and app/Resources, not ignored generated directories.
- [ ] #3 A repo hygiene check or documentation note clarifies which release artifacts are generated and should not be committed.
<!-- AC:END -->
