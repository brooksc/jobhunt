---
id: TASK-713
title: >-
  Fit scores vary by ±3 points run to run, so fine-grained ranking is noise —
  reduce variance before tuning the rubric
status: To Do
assignee: []
created_date: '2026-08-31 21:38'
labels: []
dependencies: []
priority: high
type: enhancement
ordinal: 87000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Measured 2026-08-31 by [[TASK-710]] (`scratchpad/bench-fit.md`, 550 calls, $9.17).

**Scoring the same job against the same résumé with the same prompt five times gives σ = 3.16 and a mean spread of 7.6 points. 21 of 29 jobs move ≥4 points on identical input.**

This is the most consequential number produced today, and it reframes everything else about fit scoring:

- **The top of the ranking is largely noise-ordered.** `docs/fit-scoring.md` reports the top 50 jobs spanning only 7 distinct values. With ±3 points of run-to-run variance, the ordering *within* the top band carries little information — which is exactly where the user needs it most, because that is the set they choose applications from.
- **It sets the bar for every future rubric change.** A proposed change must move scores by more than ~3 points per job to be distinguishable from doing nothing. Three of the three changes proposed in [[TASK-709]] failed that bar.
- **It is not a rubric problem.** No prompt wording fixes sampling variance. Tuning the rubric while the noise floor sits at 3 points is polishing beneath the measurement error.

## What to try, cheapest first

1. **Turn off or reduce thinking, and pin temperature.** The benchmark found actual cost is **$0.0167 per call, 43% above the $0.0117 estimate, because Gemini 3 thinking tokens bill as output** (1.23M completion/thinking tokens across 550 calls). Scoring against a rubric is a classification task, not a reasoning-heavy one. If disabling thinking and setting temperature to 0 holds accuracy, it cuts both variance and cost in one change. **Measure accuracy against the labelled fixtures before adopting** — cheaper and more repeatable is not better if it scores worse.
2. **Average N runs** for scores that matter. Expensive (linear in N) and only reduces σ by √N, so prefer 1; worth considering only for a shortlist.
3. **Reduce the prompt's dominant term.** The 45k-character résumé is ~11.1k of the ~14k prompt tokens per call. A shorter targeted résumé would cut cost substantially and may reduce variance by giving the model less irrelevant material to weigh differently between runs. The four inactive targeted résumés (~5.6–6.0 KB) are a ready comparison set. Note [[TASK-712]] found the meta-commentary effect itself is null, so this is a cost-and-variance argument, not an accuracy one.

## Then reconsider what the score is for

If variance cannot be brought well below the gaps the user cares about, a single sortable number is overselling its precision. `docs/ai-prompts-review-2026-08-31.md` §5 proposes either a stretch indicator alongside the score or renaming to `requirements_match`. Both become more attractive once it is established that fine ranking is not achievable — and that is now measured rather than assumed.

Do this before any further rubric work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Run-to-run σ is measured with thinking disabled and temperature pinned, against the same 29-job set
- [ ] #2 Accuracy against the labelled fixtures is compared before and after, not just variance
- [ ] #3 The cost per scoring call is re-measured and docs/fit-scoring.md updated with the real figure
- [ ] #4 A shorter targeted résumé is measured for its effect on both variance and cost
- [ ] #5 A decision is recorded on whether a single sortable score is defensible at the achieved noise floor
<!-- AC:END -->
