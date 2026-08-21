---
id: TASK-676
title: 17 jobs are stuck in failed extraction and nothing re-drives them
status: To Do
assignee: []
created_date: '2026-08-21 02:18'
labels:
  - bug
  - extraction
  - data
dependencies: []
priority: high
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Live store, 2026-08-20: 966 jobs extracted, 17 failed and stayed failed. They render as blank rows — no title, company, salary or fit score — so they are invisible to every filter the user triages with, and nothing retries them.

Breakdown:
- 10 x 'LLM response could not be parsed as JSON'. Job #861 (Instacart, gh_jid 8143270) is the reproducible case: captured twice (861, 987), fails all three attempts both times. The re-run with the new head+tail preview proved the response is COMPLETE at both ends (closes with "confidence": 1.0 }), so it is not truncation. The parser's own complaint is now recorded in the error message, so one more re-run of 861 names the cause.
- 5 x 'Extraction never ran — its queued request was cancelled or removed.' These need nothing but a re-run.
- 1 x 'Model response could not be parsed as valid JSON' (the JSONRepair-level message, distinct wording from the above — worth unifying).
- 1 x 'Job has no capture text to extract from' — genuinely unrecoverable without a re-capture.

Two things to decide: whether a failed extraction should be retried automatically at some later point (nothing does today), and how a permanently-failed job should present, since a blank row that can't be filtered is the worst of both worlds.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The root cause of the unparseable-JSON class is identified from the recorded parser complaint
- [ ] #2 The 5 'never ran' jobs are re-driven and extract successfully
- [ ] #3 A job whose extraction failed permanently is visible/filterable rather than a blank row
- [ ] #4 The two different 'could not be parsed' messages are unified
<!-- AC:END -->
