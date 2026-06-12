---
id: TASK-339
title: 'Release DMG: Bundle the MCP helper using the actual product path'
status: Done
assignee: []
created_date: '2026-06-12 20:35'
updated_date: '2026-06-12 20:51'
labels:
  - audit
  - release
  - dmg
  - mcp
  - packaging
dependencies: []
references:
  - Project.swift
  - README.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The JobhuntMCP target is named JobhuntMCP, but the app post-build copy script looks for ${BUILT_PRODUCTS_DIR}/jobhunt-mcp. If Xcode/Tuist emits the target product as JobhuntMCP, the helper will not be copied into Contents/Helpers at the documented path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The DMG build copies the actual MCP helper product into Jobhunt.app/Contents/Helpers/jobhunt-mcp.
- [ ] #2 The copied helper is executable and signed as part of the app/notarized artifact.
- [ ] #3 A release smoke check fails if Contents/Helpers/jobhunt-mcp is missing or not runnable.
<!-- AC:END -->
