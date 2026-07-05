---
id: TASK-600
title: 'duplicates: add a manual "Scan for Duplicates" action to the Jobs actions menu'
status: Done
assignee: []
created_date: '2026-07-05 19:55'
labels:
  - duplicates
  - ui
dependencies: []
modified_files:
  - app/Views/Jobs/JobsView.swift
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
There was no way to manually run duplicate detection — it only ran automatically after an LLM queue batch (QueueActor, when totalProcessed > 0) or via the JobhuntMigrator --detect-duplicates CLI. Users looking to re-check the existing set on demand couldn't find any action.

Added a "Scan for Duplicates" button to the Jobs view Actions (ellipsis) menu, directly below "Check Job Description Availability" (as requested). It calls BackgroundStore.detectAndPersistDomainDuplicates() — the same scan the queue runs — shows a toast with the count of newly-flagged pairs, and offers a "Review" action that navigates to the Duplicates screen. Disabled while a scan is in flight. Errors surface via toast.</description>
<parameter name="acceptanceCriteria">["A 'Scan for Duplicates' item appears in the Jobs Actions menu next to the availability check", "Running it flags new domain duplicates and toasts the count; 'Review' jumps to the Duplicates screen; 0 new → 'No new duplicates found'", "The item is disabled while scanning; errors show a toast", "App builds; lint/format clean"]
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added runDuplicateScan() + a 'Scan for Duplicates' Actions-menu item in JobsView (below the availability check) calling BackgroundStore.detectAndPersistDomainDuplicates(), with a count toast + 'Review' navigation to the Duplicates screen and an in-flight disabled state. Reuses the existing, tested detector; app builds; lint/format clean.
<!-- SECTION:FINAL_SUMMARY:END -->
