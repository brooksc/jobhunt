---
id: TASK-038
title: 'DuplicateDetector: hash + heuristic duplicate grouping'
status: In Progress
assignee:
  - claude
created_date: '2026-06-07 22:45'
updated_date: '2026-06-08 02:05'
labels:
  - swift-rewrite
  - core
milestone: m-1
dependencies:
  - TASK-034
  - TASK-036
documentation:
  - swift-plan.md
  - server/db.js
priority: medium
ordinal: 1500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port duplicate detection — the logic that flags the same posting captured from multiple sources/recaptures, powering the Duplicates screen.

## Read first
- swift-plan.md §9 (DuplicateDetector), §6.1 (Job/Capture/DuplicateDecision models), §10.2 #7 (Duplicates screen behavior, kinds: exact_hash / similar_hash).
- Legacy server/db.js — the duplicate-detection helpers (hash-based on cleaned_description; heuristic: Jaccard company match, description similarity, domain/field-conflict scoring; confidence output). Reproduce the scoring exactly.

## Implement (core/Services/DuplicateDetector.swift)
- `cleanedHash`/`rawHash` computation consistent with capture ingestion (coordinate with task-036 Cleaning + the capture pipeline task).
- Group/pair detection producing (original, candidate, similarity 0–1, reason) tuples; respect existing DuplicateDecision records (keep / mark_duplicate) so resolved pairs don't reappear.
- A `duplicateGroups()` query helper returning pairs for the UI (pair count = sum of (groupSize-1)).

## Dependencies
Depends on task-034 (models), task-036 (cleaning/hash helpers). Consumed by the Duplicates screen and JobService (set duplicate_of on ingest).

## Tests (CoreTests)
- Identical captures → exact_hash pair; near-identical → similar_hash with expected score; resolved decisions excluded; Jaccard/company-conflict scoring matches legacy on fixtures.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Exact-hash and similar-hash pairs detected with confidence matching legacy db.js scoring
- [ ] #2 Resolved DuplicateDecision records exclude pairs from results
- [ ] #3 duplicateGroups() returns UI-ready pairs; pair count math correct
- [ ] #4 CoreTests cover exact, near, and resolved cases on fixtures
<!-- AC:END -->
