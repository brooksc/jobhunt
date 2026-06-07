---
id: TASK-043
title: >-
  External one-time legacy SQLite → SwiftData migrator (standalone CLI, not
  shipped)
status: To Do
assignee: []
created_date: '2026-06-07 22:46'
labels:
  - swift-rewrite
  - tooling
  - data
milestone: m-1
dependencies:
  - TASK-034
documentation:
  - swift-plan.md
  - server/db.js
priority: low
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Build a standalone command-line tool that migrates the developer's existing legacy jobhunt.db (Electron/Node app) into a SwiftData store ONCE, off-machine. This is NOT shipped in the app (no users to migrate in-app per §0/§14).

## Read first
- swift-plan.md §6.5 (one-time external migrator — explicitly not in-app), §6.1 (table→@Model mapping), §14 (upgrade path).
- Legacy server/db.js for the exact legacy schema/column names.

## Implement (a small SPM executable, e.g. tools/migrator/ or as a JobhuntMCP-sibling target)
- Read legacy DB at `~/Library/Application Support/Jobhunt/jobhunt.db` (path overridable by arg) via the C `SQLite3` API, read-only.
- Reuse JobhuntCore's @Model types + ModelContainerFactory to write a fresh SwiftData store at a target path (arg), mapping every table → model, preserving jobNumber, rawHash/cleanedHash, timestamps, and JSON blobs verbatim.
- Print a summary (rows migrated per entity). Idempotent enough to re-run into a fresh output store.
- Document usage in a short README in the tool directory.

## Dependencies
Depends on task-034 (models + ModelContainerFactory). Standalone — no UI/server dependency.

## Tests (CoreTests or tool tests)
- Run against a copy of a real/fixture legacy DB; assert per-entity row counts match source; spot-check key fields (a job's jobNumber/company/extractedJSON) survive intact; produced store opens with the app's container.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLI reads a legacy jobhunt.db (read-only) and writes a SwiftData store usable by the app
- [ ] #2 Every table mapped; jobNumber/hashes/timestamps/JSON blobs preserved verbatim
- [ ] #3 Prints per-entity migration summary; usage documented
- [ ] #4 Test against a fixture legacy DB: per-entity counts match and key fields verified intact
- [ ] #5 Tool is excluded from the shipped app bundles
<!-- AC:END -->
