---
id: TASK-598
title: >-
  mcp: add runpath so jobhunt-mcp helper can load JobhuntCore.framework
  standalone
status: Done
assignee: []
created_date: '2026-07-05 19:40'
labels:
  - mcp
  - build
dependencies: []
modified_files:
  - Project.swift
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MCP clients (Claude) launch `jobhunt-mcp` as a bare subprocess. The JobhuntMCP target set no `LD_RUNPATH_SEARCH_PATHS`, so the helper's only rpath was `/usr/lib/swift`. It links `@rpath/JobhuntCore.framework`, so dyld couldn't resolve the framework either beside it (build-products dir) or at `../Frameworks` (inside the app bundle at Contents/Helpers/), and the tool crashed on launch before serving anything — MCP failed even with the app running. The JobhuntMigrator target already had `@executable_path` for the same reason; JobhuntMCP was missing it AND the bundle-relative path.

This is a build-config bug shared by the shipped DMG (same Project.swift), so it likely broke MCP for all DMG users, not just the dev build.

Fix: JobhuntMCP now sets `LD_RUNPATH_SEARCH_PATHS = ["$(inherited)", "@executable_path", "@executable_path/../Frameworks"]` — `@executable_path` for running from the build-products dir, `@executable_path/../Frameworks` for running from Contents/Helpers/ inside the app bundle (the documented Claude invocation path).

Separately (user-env, not code): the user's `claude mcp` config still pointed at the deleted Electron server `node server/mcp.js --db-path .data/jobhunt.db`; replaced it with the Swift bridge helper.

Verified: after tuist generate + rebuild, the helper has the two new rpaths, loads standalone, and with the app running returns a successful initialize + tools/list (12 tools) end-to-end; `claude mcp get jobhunt` shows Connected.</description>
<parameter name="acceptanceCriteria">["jobhunt-mcp built into the app bundle loads standalone (no dyld @rpath/JobhuntCore.framework failure) when launched from Contents/Helpers/", "With the app running, initialize + tools/list succeed through the helper and claude mcp reports Connected", "otool -l shows @executable_path and @executable_path/../Frameworks rpaths on the helper", "Fast gate remains green after the Project.swift change"]
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added LD_RUNPATH_SEARCH_PATHS (@executable_path + @executable_path/../Frameworks) to the JobhuntMCP target so the standalone-launched helper can resolve JobhuntCore.framework both from the build-products dir and from Contents/Helpers/ inside the app bundle. Regenerated + rebuilt; verified the helper loads and returns 12 tools end-to-end with the app running (claude mcp: Connected). Also repaired the user's stale claude mcp config (was pointing at the deleted Electron node server/mcp.js) to the Swift bridge. Note: same fix is needed in a re-released DMG for shipped installs.
<!-- SECTION:FINAL_SUMMARY:END -->
