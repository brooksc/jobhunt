---
id: TASK-186
title: >-
  Release: Bundle the MCP helper inside the DMG app or fix the documented
  install path
status: To Do
assignee: []
created_date: '2026-06-11 23:39'
labels:
  - audit
  - release
  - mcp
  - dmg
dependencies: []
references:
  - README.md
  - Project.swift
  - .github/workflows/release-dmg.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README documents `/Applications/Jobhunt.app/Contents/Helpers/jobhunt-mcp`, but `JobhuntMCP` is built as a separate command-line target and does not appear to be copied into `Jobhunt.app`. The DMG workflow packages only the exported app bundle, so users may not get the MCP helper at the documented path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The DMG release contains `jobhunt-mcp` at the documented path, or documentation points to the actual installed helper path.
- [ ] #2 A release/build verification step asserts the helper exists in the exported DMG app bundle when MCP is advertised.
- [ ] #3 MAS builds continue to exclude MCP behavior intentionally.
<!-- AC:END -->
