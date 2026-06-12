---
id: TASK-343
title: 'Release smoke checks: Assert DMG/MAS artifact contents and entitlements'
status: To Do
assignee: []
created_date: '2026-06-12 20:36'
labels:
  - audit
  - release
  - ci
  - packaging
  - smoke-test
dependencies: []
references:
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - Project.swift
  - config/entitlements/Jobhunt-DMG.entitlements
  - config/entitlements/Jobhunt-MAS.entitlements
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The DMG workflow verifies the exported app exists and is signed, but does not verify the MCP helper exists and is signed. The MAS workflow exports a pkg but does not assert MCP helper absence or inspect sandbox entitlements.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DMG release smoke checks assert Contents/Helpers/jobhunt-mcp exists, is executable, and has a valid signature.
- [ ] #2 MAS release smoke checks assert the app/pkg contains no MCP helper and no MCP-only artifacts.
- [ ] #3 Release workflows inspect signed entitlements and fail if MAS lacks sandbox/network entitlements or DMG unexpectedly has MAS-only settings.
<!-- AC:END -->
