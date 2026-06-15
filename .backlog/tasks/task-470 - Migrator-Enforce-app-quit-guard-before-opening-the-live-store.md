---
id: TASK-470
title: 'Migrator: Enforce app-quit guard before opening the live store'
status: To Do
assignee: []
created_date: '2026-06-15 03:38'
labels:
  - bug
  - migrator
  - data-safety
dependencies: []
references:
  - tools/migrator/main.swift
  - scripts/migrate-db.py
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every live-store mode in JobhuntMigrator (`--reclean`, `--backfill-models`, `--prune-orphan-fit-scores`, `--prune-orphan-attempts`, `--recompute-fit-mirrors`, `--detect-duplicates`, `--patch`, `--repair-fit-scores`) opens the production store read-write and only prints "Run with the Jobhunt app quit" — it never enforces it. The store is documented as single-writer / not multi-process-safe, so a forgotten quit means two writers on the same SQLite file and corruption. The safer pattern already exists in-repo: `scripts/migrate-db.py:43-46` does a `pgrep -x Jobhunt` precondition, but the Swift CLI did not carry it over. Fix: before opening the container in each `--store` mode, check `NSWorkspace.shared.runningApplications` for bundle id `com.jobhunt-app.jobhunt` (or shell out to pgrep) and exit(1) with a clear error if the app is running.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All --store modes exit with a clear error if the Jobhunt app is running, before opening the store
- [ ] #2 An --input/--output-only mode (not touching the live store) is unaffected
- [ ] #3 Optional override flag is documented if a force path is needed
<!-- AC:END -->
