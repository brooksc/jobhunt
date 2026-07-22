---
id: TASK-625
title: >-
  Duplicates review UX: advance to next on resolve, sticky/larger compare width,
  remove Delete
status: To Do
assignee: []
created_date: '2026-07-22 21:13'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Three review-screen fixes:
1. Resolving a pair (Mark as Duplicate / Keep Both) now advances to the NEXT pair in the list (or the new last), instead of deselecting — so the user can work through the queue without re-selecting.
2. The pair-list/compare split is now a manual HStack with a draggable divider whose width is persisted via @AppStorage (default 440, range 300–760). Previously HSplitView reset the compare panel's width on every resolve and didn't persist; now the compare panel is sticky, resizable, and defaults wider to use the space.
3. Removed Delete from the review screen entirely (header button + "Discard this one"). Per user: Mark as Duplicate is strictly better — it keeps the record + a DuplicateDecision so the same posting can't be re-captured into the review queue, whereas Delete loses that memory and re-surfaces on re-capture. A genuine junk job can still be deleted from the Jobs list.
<!-- SECTION:DESCRIPTION:END -->
