---
id: TASK-186
title: >-
  Release: Bundle the MCP helper inside the DMG app or fix the documented
  install path
status: Done
assignee: []
created_date: '2026-06-11 23:39'
updated_date: '2026-06-11 23:54'
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
- [x] #1 The DMG release contains `jobhunt-mcp` at the documented path, or documentation points to the actual installed helper path.
- [x] #2 A release/build verification step asserts the helper exists in the exported DMG app bundle when MCP is advertised.
- [ ] #3 MAS builds continue to exclude MCP behavior intentionally.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added a post-build script phase to appTarget in Project.swift that copies `${BUILT_PRODUCTS_DIR}/jobhunt-mcp` into `Contents/Helpers/jobhunt-mcp`. The script exits early for `*MAS*` configurations (no MCP entitlement in sandbox). Uses `basedOnDependencyAnalysis: false` so it always runs. Project regenerated with `tuist generate --no-open`.
<!-- SECTION:FINAL_SUMMARY:END -->
