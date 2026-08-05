---
id: TASK-661
title: >-
  Thorough model evaluation — the public recommendation page is live on two data
  points
status: To Do
assignee: []
created_date: '2026-08-05 18:12'
updated_date: '2026-08-05 19:31'
labels:
  - llm-eval
  - docs
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Prerequisite for the "Which AI model to use?" page — that page must not present a model as tested when it isn't.

**What is actually measured today.** The fit-judgement eval (`tests/LLMEval/FitScoringEval.swift`, `OverCreditEval.swift`, run via the opt-in `Jobhunt-Eval` scheme) has been run against exactly two models:

| Model | Result |
|---|---|
| `openrouter:deepseek/deepseek-v4-flash-0731` | **7/7** |
| `openrouter:google/gemini-3.1-flash-lite` | 5/7 |

`~/.config/jobhunt/eval-models` also lists `anthropic/claude-haiku-4.5` and `google/gemini-3.5-flash-lite`. Those are **configured, not benchmarked** — no numbers exist for them.

**Work**

1. Run the eval across all four configured models and record the results somewhere durable (the eval README, or a committed results file). Fixtures are derived from real failures — #231's hardware/controls over-credit, #718's "capacity to learn" — so a pass rate here means something concrete.
2. **Capture cost, not just accuracy.** The whole selection criterion is "good enough at a low price", and today only accuracy is recorded. `CostEstimator.estimateCost` already computes spend from token counts and `fetchOpenRouterPricing` can pull live per-1M rates, so the harness can emit **$ per 100 jobs** per model from the same run that produces the pass rate.
3. Note qualitative failure modes, not just the score. `gemini-3.1-flash-lite` didn't merely score lower — it *regressed* when the prompt grew (job #231 went from a correct 60 back to 96 when one broad rule was added). "Sensitive to prompt changes" is exactly the kind of thing a user choosing a model wants to know, and it won't show up in a pass count.
4. Consider adding a frontier model as a **ceiling reference** so the page can say what the cheap models cost you in accuracy, rather than implying the cheap one is simply best.

**Caveat that invalidates results if ignored:** the résumé exists in two copies — the scorer reads `ZRESUME` in the store, the eval reads `~/.config/jobhunt/eval-resume.md`. They have been stale together before, so the eval passed while the shipping scorer was working from an out-of-date résumé. Confirm the two match before treating any run as authoritative.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All four models in eval-models have a recorded pass rate from the same fixture set
- [ ] #2 Each model has an estimated $ per 100 jobs derived from measured token counts, not guessed
- [ ] #3 Qualitative failure modes are recorded, including prompt-sensitivity, not only the score
- [ ] #4 Results live in a committed file the marketing page can be generated from or checked against
- [ ] #5 The eval resume and the store resume are confirmed identical before results are treated as authoritative
- [ ] #6 Local models (LM Studio/Ollama) have a measured accuracy result, so the privacy recommendation states its real cost
- [ ] #7 The rolling deepseek/deepseek-v4-flash alias is benchmarked, or the page recommends the pinned snapshot that was
- [ ] #8 Fixtures cover extraction quality (malformed JSON, missed salary, wrong remote status), not only fit judgement
- [ ] #9 marketing/help/which-model.html is regenerated from the committed results, with no hand-entered numbers left
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Now urgent rather than merely useful: the page shipped.** `marketing/help/which-model.html` is public (TASK-662), and it carries a recommendation under our name. Three of the five models in its cost table are marked untested — honest, but thin — and the whole page rests on a 7-case fixture set run against two models.

What the page needs from this task, specifically:

1. **Fill the untested rows.** Gemini 3.5 Flash Lite, Claude Haiku 4.5 and Claude Sonnet 5 are priced there but carry a "—" for accuracy. Sonnet 5 costs 17x the recommendation; the page currently says we haven't measured whether that buys anything, which is true and unsatisfying.
2. **Benchmark local models.** The page recommends LM Studio / Ollama for privacy while admitting we can't say what accuracy it costs. That's the single biggest gap for a privacy-motivated reader, and it's the option that costs them nothing to try.
3. **Grow the fixture set.** Seven cases is enough to separate a good model from a bad one and not enough to rank close ones. It should also cover *extraction* quality (malformed JSON, missed salary, wrong remote status), not only fit judgement — extraction failures are what actually break a user's corpus.
4. **Settle the snapshot-vs-rolling question.** The benchmark ran `deepseek/deepseek-v4-flash-0731`; the app and the page recommend the rolling `deepseek/deepseek-v4-flash`, which is a different (and pricier: $0.14/$0.28 vs $0.09/$0.18 per 1M) pointer. We are recommending something adjacent to what we measured. Either test the rolling alias or recommend the pinned snapshot.
5. **Make the numbers regenerable.** Prices moved into the page by hand today. They should come from a committed results file so refreshing the page is a re-run, not a rewrite.

Token basis used for the published costs, for reproducibility: ~5,522 input / 450 output tokens per job, from the app's own Cost Estimate over a 15-job corpus. Real postings run longer, so treat published figures as a floor.
<!-- SECTION:NOTES:END -->
