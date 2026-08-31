---
id: TASK-711
title: >-
  Make the fit-score rubric version queryable, so stale scores can be found and
  rescored in bulk
status: To Do
assignee: []
created_date: '2026-08-31 21:05'
updated_date: '2026-08-31 21:09'
labels: []
dependencies: []
priority: high
type: enhancement
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From `docs/ai-prompts-review-2026-08-31.md` §7, and asked directly by the user 2026-08-31: *"Do we track also which fit score version was used, so I can find any not on the latest and rescore those?"*

**We track it, but not where anything can use it.** `assessment_prompt_version` lives *inside* the `fitScoreJSON` blob; `ZJOBFITSCORE` has no version column. Nothing can filter, sort or index on it, so there is no way to answer "show me every score not on the current rubric."

## Why this is urgent, with numbers

Measured on the live store today:

| version | n | mean | median | p25 | p75 |
|---|---|---|---|---|---|
| v1 | 977 | **68.9** | 74.0 | 56 | 89 |
| v2 | 12 | 94.7 | 96.0 | 94 | 97 |
| v3 | 823 | **50.0** | 50.0 | 31 | 70 |

**A 19-point mean gap between rubrics, and v1 is 54% of the corpus.** Every sort and every `min_score` filter over the whole library is therefore systematically biased toward the older, more generous population: a v1 score of 74 and a v3 score of 74 are not the same claim, and the v3 job is much the better match.

This also corrects an earlier reading. `docs/fit-scoring.md` reports a near-flat corpus-wide distribution with mean 53 and calls the scoring well calibrated. That distribution is a **blend of two incompatible populations** — the flatness is partly an artifact of overlaying a generous rubric on a harsh one. v3 alone is genuinely well spread (median 50, quartiles 31/70), so the current rubric does discriminate; the corpus-wide figure does not support the conclusion drawn from it.

## What to build

- Promote `assessment_prompt_version` to a real stored property on the fit-score model so it is queryable. Per CLAUDE.md's schema policy make it **optional** (3 stored scores are unversioned). Backfill it from the existing JSON — no LLM calls needed, same shape as the `--repair-remote-types` and `--repair-salaries` modes.
- Surface the version where the score is shown, and flag a score produced by a superseded rubric. `reflects_previous_resume_version` is the existing precedent for exactly this kind of staleness marker — and rubric staleness is more consequential, because a résumé change moves one job's score while a rubric change moves the whole ranking.
- Either exclude non-current versions from `min_score` and the default sort, or show a count of stale scores with a one-click rescore.

## Cost of actually rescoring

Measured, not estimated: fit calls average 8,858 prompt / 1,351 completion tokens on `gemini-3.7-flash` at $0.75/M in and $3.75/M out (introductory, through 2026-12-31), so **$0.0117 per score** with one active résumé. Rescoring all 977 v1 scores is **≈ $11.44**, or **≈ $5.72** on the Batch API at half price — latency being irrelevant for a backfill. Cost is not the constraint; rubric confidence is, which is why [[TASK-710]] comes first.

Sequencing: this is independent of [[TASK-709]] and can land before it. Doing so first means the v4 bump arrives with the tooling already in place to find and clear everything older.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 assessment_prompt_version is a queryable optional stored property, backfilled from existing JSON with no LLM calls
- [ ] #2 A command-line path lists how many stored scores are on each rubric version
- [ ] #3 A command-line path rescores every score not on the current version, resumable and idempotent
- [ ] #4 docs/fit-scoring.md's corpus-wide distribution claim is corrected to note it blends v1 and v3
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: primary
created: 2026-08-31 21:09
---
Scope narrowed 2026-08-31 on the user's call: **no UI filter.** "I don't know we need a filter, that's not useful for anyone but me." Correct — a stale-version chip in the Jobs sidebar is maintenance weight for an audience of one, and it would sit in the UI forever to serve a problem that exists only while old scores do.

What is actually needed is the ability to **find and clear** stale scores, which is a one-off bulk operation, not a permanent affordance. That belongs in `JobhuntMigrator` alongside `--repair-salaries` and `--repair-remote-types`: a mode that reports the version histogram, and a mode that rescores everything not on the current version.

The queryable column is still worth having — without it neither mode can select its work set without parsing every JSON blob — but it exists to serve the migrator, not a screen.

Dropped acceptance criteria: the UI filter, the per-score staleness badge, and excluding stale versions from `min_score`/default sort. If ranking across mixed versions turns out to mislead in practice, that is a separate decision to make with evidence rather than pre-emptively.
---
<!-- COMMENTS:END -->
