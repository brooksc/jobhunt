---
id: TASK-676
title: 17 jobs are stuck in failed extraction and nothing re-drives them
status: Done
assignee: []
created_date: '2026-08-21 02:18'
updated_date: '2026-08-22 20:36'
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
- [x] #1 The root cause of the unparseable-JSON class is identified from the recorded parser complaint
- [x] #2 The 5 'never ran' jobs are re-driven and extract successfully
- [x] #3 A job whose extraction failed permanently is visible/filterable rather than a blank row
- [x] #4 The two different 'could not be parsed' messages are unified
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
17 failed → 1, and that one is genuinely unrecoverable (job #94, archived, "Job has no capture text to extract from" — it needs a re-capture, not a re-run). Live store now: 982 succeeded, 1 failed.

**#1 root cause.** `repairJSON` applied every transform and only then validated. Responses that were already valid JSON got rewritten by the repair steps into something that no longer parsed — job #861 failed three times against a response that was complete and well-formed at both ends. Fixed by parsing first (returning the input untouched when it's already valid), then applying steps cumulatively and stopping at the first that parses.

**#2** The 5 "never ran" jobs, and the unparseable class, were re-driven and extracted successfully.

**#3** Already satisfied by `QualityIssueKind.extractionFailed` — high severity, with its own Data Quality filter chip — but nothing tested it, so nothing stopped it regressing. Now covered, including that `.pending` must not trip it (TASK-459). Archived failures stay out of Data Quality by `DataQualityScope.isEligible`, which is deliberate.

**#4** `jsonParserComplaint` / `jsonParseFailureMessage` moved into JSONRepair, beside the parsing, so both call sites report the same sentence and both carry the parser's positional complaint. The complaint remains the parser's, never the model's text — these strings reach logs and the UI.

Not done, deliberately: nothing retries a failed extraction automatically. Given the failure class turned out to be a bug in our own repair pass rather than a flaky model, an automatic retry loop would have been papering over it. Worth revisiting only if failures reappear at volume.
<!-- SECTION:FINAL_SUMMARY:END -->
