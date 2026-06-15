---
id: TASK-476
title: >-
  Migrator Patch: Abort patch on per-job save failure instead of logging and
  continuing
status: Done
assignee: []
created_date: '2026-06-15 03:39'
updated_date: '2026-06-15 06:48'
labels:
  - bug
  - migrator
  - data-safety
dependencies: []
references:
  - tools/migrator/Patch.swift
modified_files:
  - tools/migrator/Patch.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`Patch.swift:100` calls `context.save()` inside the per-job insert loop and again at the end (line 110). If a mid-loop save throws, it is printed to stderr and the loop continues, so the run reports success-ish output while some jobs/relationships are inconsistent. Unlike `migrate()`, `patch()` has no all-or-nothing semantics. Fix: on save failure, abort the patch (return early / propagate) rather than printing and continuing.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
patch() now exit(1)s with a clear stderr message on a per-job context.save() failure (both the per-job save and the final relationship save) instead of logging and continuing — so a failed patch can no longer silently report success-ish output while leaving some jobs/relationships inconsistent. Matches the migrator's established exit-on-error pattern; migrate() already had all-or-nothing semantics.
<!-- SECTION:FINAL_SUMMARY:END -->
