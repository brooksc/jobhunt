---
id: TASK-038
title: 'DuplicateDetector: hash + heuristic duplicate grouping'
status: Done
assignee:
  - claude
created_date: '2026-06-07 22:45'
updated_date: '2026-06-08 02:11'
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
modified_files:
  - core/Services/DuplicateDetector.swift
  - tests/CoreTests/DuplicateDetectorTests.swift
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
- [x] #1 Exact-hash and similar-hash pairs detected with confidence matching legacy db.js scoring
- [x] #2 Resolved DuplicateDecision records exclude pairs from results
- [x] #3 duplicateGroups() returns UI-ready pairs; pair count math correct
- [x] #4 CoreTests cover exact, near, and resolved cases on fixtures
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented DuplicateDetector.swift in core/Services/ with:

1. **Exact-hash detection**: Groups jobs by cleanedHash (SHA-256 of cleaned description). Same hash from different URLs = exact_hash pair with confidence 1.0.

2. **Domain-heuristic detection** (faithful port of detectDomainDuplicateJobs from server/db.js):
   - Groups by normalized title, then clusters by company Jaccard similarity (≥0.5 threshold, stop-words filtered)
   - Ranks by companyDomainScore (company.com=100, direct label=90, ATS platform=45, etc.)
   - Requires ≥2 distinct hostnames per cluster and clear winner (no tie)
   - Confidence formula: `0.65 + (scoreDiff/100)*0.24 ± descAdj - fieldPenalty`
   - Description similarity: Jaccard on word sets (min 8 tokens, stop-words filtered)
   - Salary hard-block: >10% divergence on both bounds → nil (blocked)
   - Field penalties: 0.08 per conflicting field (remote_type, employment_type, seniority, location, salary_currency)

3. **Resolved pair exclusion**: DuplicateDecision records (by cleanedHash) are fetched and excluded before results are returned.

4. **duplicateGroups(context:)**: Takes a ModelContext, queries Job+Capture+DuplicateDecision, returns [DuplicatePair] sorted by confidence descending. Deduplicates overlapping exact/similar pairs, preferring exact_hash.

5. **Hash helpers**: `cleanedHash(from:)` and `rawHash(url:canonicalURL:selectedText:visibleText:structuredData:)` use CryptoKit SHA256 with sortedJSON serialisation matching db.js exactly.

22 XCTest cases in DuplicateDetectorTests.swift covering all acceptance criteria. All 31 CoreTests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
