---
id: TASK-661
title: >-
  Benchmark the remaining configured models, and record cost per job alongside
  pass rate
status: To Do
assignee: []
created_date: '2026-08-05 18:12'
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
<!-- AC:END -->
