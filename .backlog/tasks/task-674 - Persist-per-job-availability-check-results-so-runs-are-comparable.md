---
id: TASK-674
title: Persist per-job availability check results so runs are comparable
status: To Do
assignee: []
created_date: '2026-08-20 21:00'
labels:
  - availability
  - ux
  - schema
dependencies: []
priority: high
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A user ran the archive availability check twice over an unchanged set of 401 archived jobs and got 7 gone, then 4, with no way to tell why. Confirmed from the store that the population did not change between runs (archived 401, expired 242 both times), so the difference was in the checking, not the data.

Two mechanisms cause run-to-run variation, both legitimate individually and both invisible:
1. LinkedIn is checked 12 per run by rotation, so each run covers a different subset (rotation offset was 240, i.e. ~20 runs in).
2. An ATS board answer is only used when definitive. A 429/5xx/timeout means 'don't know', and the job then falls back to page heuristics that correctly refuse to judge a client-rendered shell — so a THROTTLED board call silently moves a job from 'gone' to 'couldn't verify' and it drops out of the list. TASK-672 follow-up work added ATSResponseCache (coalescing + short TTL, definitive answers only) which removes most of that throttling, but does not make results comparable.

Nothing is stored per job: ZJOB has no availability columns, so every run re-checks from scratch and no run can be compared with the last. The user cannot answer 'is this new, or did I just not see it last time?', and neither can the app.

Proposal: store the outcome of each check on the job — checked-at, verdict (alive/gone/unverified), reason, and which source answered (ATS board vs page heuristic vs LinkedIn guest). Then:
- the confirmation sheet can mark each row 'also flagged last time' vs 'new since <date>'
- a job whose only 'gone' evidence is one un-reproduced check can be held back from the default selection
- the LinkedIn rotation becomes legible ('last checked 6 days ago') instead of mysterious
- a future background drip (TASK-673) has somewhere to record its findings

Schema note: additive optional attributes should be a lightweight SwiftData migration, but this is the first model change in a while — see TASK-480 on SchemaV2 readiness before starting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each availability check records checked-at, verdict, reason and answering source on the job
- [ ] #2 The confirmation sheet distinguishes newly-gone postings from ones flagged in a previous run
- [ ] #3 A gone verdict that a later run could not reproduce is visible as such rather than silently disappearing
- [ ] #4 Rows show when they were last checked, so LinkedIn's rotation is legible
- [ ] #5 The migration is additive and an existing store opens without data loss
<!-- AC:END -->
