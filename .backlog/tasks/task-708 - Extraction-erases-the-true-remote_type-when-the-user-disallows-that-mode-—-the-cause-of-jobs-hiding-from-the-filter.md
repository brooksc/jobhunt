---
id: TASK-708
title: >-
  Extraction erases the true remote_type when the user disallows that mode — the
  cause of jobs hiding from the filter
status: To Do
assignee: []
created_date: '2026-08-31 20:39'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the 2026-08-31 extraction audit (`scratchpad/audit-extraction.md`). **Verified against the store.** This is the root cause behind [[TASK-705]] — the user's report that clearly-not-remote jobs don't appear under the "Doesn't meet criteria" filter.

`core/LLM/ExtractionEngine.swift:232-241`, added by TASK-270:

```swift
// Clamp remoteType to nil when the user has disallowed that mode.
if settings.locationFilterEnabled, let rt = remoteType {
    let allowed = (rt == .remote && settings.locationAllowRemote)
               || (rt == .hybrid && settings.locationAllowHybrid)
               || (rt == .onsite && settings.locationAllowOnsite)
               || rt == .unknown
    if !allowed { remoteType = nil }
}
```

**The model was right every time.** Of the 49 New jobs with a NULL `remoteType`, every one has a valid answer preserved in `ZEXTRACTEDJSON`: **40 `hybrid`, 9 `onsite`.** Examples: job 1078 `onsite`/San Francisco, 1140 `hybrid`/United States, 1186 `onsite`/San Mateo CA. Job #1424 (Lehi, Utah) is the reported case.

## Why this is backwards

The clamp confuses two different statements: *"the user doesn't want this kind of job"* and *"this fact must not be recorded."* Filtering on a value is `LocationCriteria`/`JobFilterRules`' job, and they already do it correctly. The clamp is a second, **lossy** filter in the wrong layer — it destroys the evidence the real filter needs.

The consequences cascade:

- `JobFilterRules.criteriaBucket(meetsCriteria: false, remoteType: nil)` returns `.notStated`, so the job **hides from the "Doesn't meet criteria" filter** — the user's original complaint. 49 in New; also ~148 archived, 62 duplicate, 9 expired, 3 applied, 1 rejected.
- `QualityIssue.swift:109` flags the now-missing field as a **data-quality defect**, so the app reports a problem it created.
- **Saved searches can never match these jobs** on remote type, because the value isn't there.
- The comment's stated goal — "so disallowed modes are never persisted" — is achieved, but the value is persisted anyway in `extractedJSON`. The clamp only strips the *queryable* copy.

## Fix

Remove the clamp and let the true value persist. Before deleting, check TASK-270's original motivation — if something downstream genuinely relied on disallowed modes never being stored, fix that instead and record what it was. The prompt-side preference for allowed modes can stay; that's a hint, not a mutation.

**Backfill costs no LLM calls.** The correct values are in `ZEXTRACTEDJSON` on every affected row, so a migrator mode can restore `remoteType` by re-reading stored JSON, then recompute `meetsCriteria` for the rows it changed. Per CLAUDE.md that belongs in `JobhuntMigrator`, run deliberately with the app quit.

## Related, from the same audit

8 jobs have a *wrong* location — a company-office list lifted from prose (1041 Cohere, 1290 Diligent, others). That is [[TASK-693]], now fixed going forward; those 8 need the same backfill pass.

Also worth recording, because it closes off wasted investigation: the audit examined all 72 gap cases and **exonerated the cleaner and the truncation cap**. Across 24 captures where cleaned ≠ visible, `Cleaning.swift` removed only whitespace, one `<!--WEB-ONLY-->` marker and three non-breaking hyphens. Longest description is 12,190 chars against a 100k cap. Of 51 missing salaries, 50 are genuinely absent from the posting. There is no model-miss or normalization-loss problem here.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The true remote_type from extraction is persisted regardless of the user's allowed modes
- [ ] #2 TASK-270's original motivation is checked and either addressed elsewhere or recorded as obsolete
- [ ] #3 Job #1424 and the other 48 New jobs appear under the Doesn't-meet filter
- [ ] #4 QualityIssue no longer reports a missing remote type it caused
- [ ] #5 A migrator mode restores remoteType for affected rows from extractedJSON, with no LLM calls, and recomputes meetsCriteria for rows it changes
<!-- AC:END -->
