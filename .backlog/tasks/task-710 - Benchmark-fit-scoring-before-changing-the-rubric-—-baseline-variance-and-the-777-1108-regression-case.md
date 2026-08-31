---
id: TASK-710
title: >-
  Benchmark fit scoring before changing the rubric — baseline, variance, and the
  777/1108 regression case
status: To Do
assignee: []
created_date: '2026-08-31 21:04'
labels: []
dependencies: []
priority: high
type: spike
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Requested by the user 2026-08-31: benchmark before implementing the rubric changes in [[TASK-709]], including the flagged jobs and the updated résumé.

Everything in `docs/ai-prompts-review-2026-08-31.md` is reasoned, not measured — the review says so itself. Shipping a rubric change on reasoning alone would replace one uncalibrated rubric with another and add a fourth incomparable version to the store.

## What to measure, before touching the prompt

1. **Run-to-run variance on the current rubric.** Score the same jobs against the same résumé N times (5 is probably enough) with no changes, and report the spread. **This is the single most important number and nothing else can be interpreted without it.** The review notes the top 50 jobs span only 7 distinct values; if the noise floor is ±3, then chasing tie-breaks — and possibly the whole 1108-vs-777 four-point inversion — is chasing noise.

2. **A baseline on the current v3 rubric** over a fixed job set, so post-change numbers are comparable. Include the hand-labelled fixtures in `tests/LLMEval` and over-sample the population the review says is mis-scored: roles whose *function* differs from the employer's product (corporate IT, finance ops, trust and safety, workplace, GTM ops).

3. **The named regression case: job 777 must rank above job 1108.** Currently 90 vs 94. Record both the current and post-change ordering.

4. **The résumé change.** `Brooks_Cutter_Resume_Master` was edited today (2026-08-31 21:01) and shrank from ~51,755 to ~45,104 characters — the review's §6 says roughly 6,800 characters of agent-facing meta-commentary ("do not claim X") were removed, which the scorer had been reading as facts about the candidate. **Re-score a sample against both the old and new résumé text to quantify the effect.** If it moves scores materially, that alone changes the interpretation of every stored score and should be stated in [[TASK-711]].

5. **Cost per run, measured not estimated.** From the store today: fit calls average 8,858 prompt tokens and 1,351 completion tokens on `gemini-3.7-flash` ($0.75/M in, $3.75/M out through 2026-12-31), so about **$0.0117 per score**. A 5× variance run over 50 jobs is roughly $3.

## Deliverable

A short report with the variance figure, the baseline table, and a go/no-go on each of TASK-709's three changes. Explicitly state which conclusions the variance floor makes unsupportable — an honest "this difference is inside the noise" is a valid and valuable result.

## Constraints

This needs real API calls and the user's key, so it is opt-in and must be run deliberately, not in CI. Do not run it without the user's say-so. `tests/LLMEval` is the existing opt-in eval target and is the right home.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Run-to-run variance on the unchanged rubric is measured and reported as a number
- [ ] #2 A v3 baseline exists over a fixed job set, over-sampling roles whose function differs from the employer's product
- [ ] #3 The current and post-change ordering of jobs 777 and 1108 is recorded
- [ ] #4 The effect of the résumé meta-commentary removal is quantified against a sample
- [ ] #5 Each of TASK-709's three changes gets an evidence-based go/no-go
- [ ] #6 Conclusions that fall inside the variance floor are identified as unsupportable
<!-- AC:END -->
