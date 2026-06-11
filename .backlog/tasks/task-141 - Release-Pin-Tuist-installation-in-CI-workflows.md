---
id: TASK-141
title: 'Release: Pin Tuist installation in CI workflows'
status: To Do
assignee: []
created_date: '2026-06-11 03:40'
labels:
  - release
  - ci
  - tuist
  - reproducibility
dependencies: []
references:
  - .github/workflows/swift-build.yml
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - README.md
  - Tuist.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The release workflows install Tuist via the latest installer script, while README names a specific Tuist version. Pinning avoids release-time project generation drift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI and release workflows install a pinned Tuist version or use a project-managed Tuist install mechanism.
- [ ] #2 The pinned version matches the documented development requirement or the docs are updated to match CI.
- [ ] #3 A dependency update process is documented for bumping Tuist intentionally.
- [ ] #4 Release workflows no longer depend on unpinned latest Tuist behavior.
<!-- AC:END -->
