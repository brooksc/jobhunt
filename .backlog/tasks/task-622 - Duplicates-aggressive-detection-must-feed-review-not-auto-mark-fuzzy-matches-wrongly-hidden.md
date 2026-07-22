---
id: TASK-622
title: >-
  Duplicates: aggressive detection must feed review, not auto-mark (fuzzy
  matches wrongly hidden)
status: Done
assignee: []
created_date: '2026-07-22 20:27'
updated_date: '2026-07-22 20:47'
labels: []
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After TASK-620 made detection aggressive/recall-first (for user REVIEW), both auto-mark paths — detectAndPersistDomainDuplicates (end-of-drain + manual scan) and detectDuplicateForJob (per-extraction) — auto-set status=.duplicate for ANY match, including fuzzy same-company/similar-title ones. Because reviewSnapshots excludes status==.duplicate, the auto-marked jobs vanish from the Duplicates review screen (user saw "9 new duplicates → Review → nothing listed") AND from their status lists (no browsable .duplicate filter). 34 of 40 marked-duplicate jobs came from the fuzzy path, including false positives (e.g. Deepgram #291 "…- AI Tooling & Systems", a distinct role, hidden as a dup of #290).

Fix (committed): only AUTO-mark DEFINITIVE matches (exactHash + atsPostingID, confidence 1.0); fuzzy (similarHash) pairs stay unmarked and surface in the review screen for the user to confirm.

Still needed: recover the ~34 already-wrongly-auto-marked jobs (clear duplicateOfJobID + restore prior status). Prior status was overwritten to .duplicate without a status event; reconstruct from the last "status" JobEvent, default pursuing. Build as a JobhuntMigrator one-shot.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Root cause: TASK-620 made duplicate detection aggressive/recall-first (for user REVIEW), but the two auto-mark paths (detectAndPersistDomainDuplicates end-of-drain+manual-scan, detectDuplicateForJob per-extraction) set status=.duplicate for ANY match. reviewSnapshots excludes .duplicate jobs, so auto-marked candidates vanished from the review screen ("9 found → Review → nothing") and from status lists. 34 of 42 marked-duplicate jobs came from the fuzzy path, including false positives (Deepgram #291 "…- AI Tooling & Systems" hidden as a dup of #290).

Fix: both auto-mark paths now gate on pair.kind == .exactHash || .atsPostingID (confidence 1.0 = the same posting). Fuzzy (similarHash) matches stay real, fit-scorable jobs and surface in the Duplicates review screen to confirm.

Recovery: BackgroundStore.unmarkHeuristicDuplicates() + JobhuntMigrator --unmark-heuristic-duplicates. Un-marks jobs whose latest duplicate_detected event is fuzzy, restoring status from the last status event (default pursuing); keeps definitive marks. Ran against the live store (app quit + backup): 34 recovered (duplicate 42→8, pursuing 77→110), 3 definitive kept, integrity ok. App rebuilt+relaunched with the fix.

Tests: fuzzy-not-auto-marked (detectDuplicateForJob + detectAndPersist), recovery restores+keeps-definitive+idempotent, and the end-to-end workflow test updated (fuzzy cross-post is a review candidate, not auto-marked).
<!-- SECTION:FINAL_SUMMARY:END -->
