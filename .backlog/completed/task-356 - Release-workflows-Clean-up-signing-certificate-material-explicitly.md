---
id: TASK-356
title: 'Release workflows: Clean up signing certificate material explicitly'
status: Done
assignee: []
created_date: '2026-06-12 20:44'
updated_date: '2026-06-12 21:53'
labels:
  - audit
  - supply-chain
  - release
  - signing
dependencies: []
references:
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Release workflows decode signing certificates into .p12 files and create build.keychain, but do not explicitly delete the p12 files or keychain at job end. Runners are ephemeral, but signing secret cleanup should be explicit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release workflows remove decoded .p12 files after import.
- [ ] #2 Release workflows delete or lock the temporary keychain in an always-run cleanup step.
- [ ] #3 Cleanup behavior is present in both DMG and MAS release jobs.
<!-- AC:END -->
