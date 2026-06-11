---
id: TASK-141
title: 'Release: Pin Tuist installation in CI workflows'
status: Done
assignee: []
created_date: '2026-06-11 03:40'
updated_date: '2026-06-11 20:38'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added .mise.toml pinning tuist = "4.196.1" (matches locally installed version). Updated all three CI workflows to use `mise install tuist` instead of unpinned installs (swift-build.yml used `brew install tuist`, release workflows used `curl -Ls https://install.tuist.io | bash`). macos-latest GitHub Actions runners have mise pre-installed so no separate mise setup step is needed. Added Dependency versions section to CONTRIBUTING.md documenting how to intentionally bump the Tuist version.
<!-- SECTION:FINAL_SUMMARY:END -->
