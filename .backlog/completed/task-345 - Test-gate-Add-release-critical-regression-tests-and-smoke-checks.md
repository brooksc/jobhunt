---
id: TASK-345
title: 'Test gate: Add release-critical regression tests and smoke checks'
status: Done
assignee: []
created_date: '2026-06-12 20:39'
updated_date: '2026-06-12 20:51'
labels:
  - audit
  - tests
  - ci
  - release
  - coverage
dependencies: []
references:
  - tests/CoreTests/BackupServiceTests.swift
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The current fast/release gates run Core, Server, MCP, and extension tests but do not protect several audited release-critical paths: backup restore replacement, WAL/SHM cleanup, invalid backup schema rejection, DMG helper contents, and MAS entitlements/artifact contents.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BackupService tests cover restore success, restore failure atomicity, real -wal/-shm cleanup, and invalid Jobhunt schema rejection.
- [ ] #2 DMG release checks assert the MCP helper exists, is executable, and is signed.
- [ ] #3 MAS release checks assert no MCP helper is present and signed entitlements match the sandbox/network requirements.
<!-- AC:END -->
