---
id: TASK-622
title: >-
  Duplicates: aggressive detection must feed review, not auto-mark (fuzzy
  matches wrongly hidden)
status: To Do
assignee: []
created_date: '2026-07-22 20:27'
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
