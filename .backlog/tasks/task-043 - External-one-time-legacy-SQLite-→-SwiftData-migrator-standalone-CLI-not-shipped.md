---
id: TASK-043
title: >-
  External one-time legacy SQLite → SwiftData migrator (standalone CLI, not
  shipped)
status: Done
assignee:
  - claude
created_date: '2026-06-07 22:46'
updated_date: '2026-06-08 02:20'
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
- [x] #1 CLI reads a legacy jobhunt.db (read-only) and writes a SwiftData store usable by the app
- [x] #2 Every table mapped; jobNumber/hashes/timestamps/JSON blobs preserved verbatim
- [x] #3 Prints per-entity migration summary; usage documented
- [x] #4 Test against a fixture legacy DB: per-entity counts match and key fields verified intact
- [x] #5 Tool is excluded from the shipped app bundles
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented the JobhuntMigrator standalone CLI tool:

- tools/migrator/main.swift: Full migration from legacy SQLite jobhunt.db to SwiftData store. Opens source DB read-only (SQLITE_OPEN_READONLY). Maps all 15 legacy tables (captures, jobs, events, site_reviews, duplicate_decisions, settings, job_actions, data_quality_reviews, sites, resumes, job_fit_scores, llm_requests, llm_request_attempts, contacts, cover_letters) to their JobhuntCore @Model counterparts. Preserves jobNumber, rawHash/cleanedHash, timestamps (ISO8601 parse), and JSON blobs verbatim. Prints per-entity summary. Falls back to defaults for unknown enum rawValues.

- tools/migrator/README.md: Usage documentation including CLI options, example invocations, post-migration steps, and a full table mapping.

- Project.swift: Added JobhuntMigrator target (commandLineTool, bundleId com.jobhunt-app.jobhunt.migrator, sources tools/migrator/**/*.swift, depends on JobhuntCore). Added to DMG scheme build action; excluded from MAS scheme.

- Tests/CoreTests/MigratorTests.swift: Three tests — (1) non-existent DB path returns SQLITE error and creates no file, (2) empty DB with minimal schema produces 0-row SwiftData store, (3) fixture DB with 1 row per key table migrates correctly with spot-checks on jobNumber=42, rawHash="hash_abc", extractedJSON preserved, and capture relationship linked.

Build: xcodebuild Jobhunt-DMG scheme succeeds. All CoreTests pass including MigratorTests.
<!-- SECTION:FINAL_SUMMARY:END -->
