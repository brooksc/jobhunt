---
id: TASK-624
title: 'Duplicates: never auto-mark; add soft Mark as Duplicate in the review screen'
status: To Do
assignee: []
created_date: '2026-07-22 21:03'
labels: []
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Per user: never auto-mark any job as a duplicate without explicit user action, and give the review screen a reversible resolution.

Changes:
- Removed all auto-marking call sites: QueueActor end-of-drain detectAndPersistDomainDuplicates and per-extraction detectDuplicateForJob (every job is now fit-scored; a suspected dup stays real until confirmed). The manual "Run Duplicate Scan" no longer persists — it counts reviewable pairs (BackgroundStore.reviewablePairCount, no writes) and jumps to the review screen.
- DuplicatesView: added "Mark as Duplicate" (primary, reversible — markDuplicate + a "duplicate" DuplicateDecision), relabeled "Unmark" → "Keep Both", and demoted "Delete" from prominent-red to a secondary button. So resolving a duplicate is a soft, reversible mark by default, not a destructive delete.

Context: TASK-620/622 exposed that aggressive detection + auto-marking hid jobs; the review screen only offered Delete (destructive) or Keep Both, with no soft mark.
<!-- SECTION:DESCRIPTION:END -->
