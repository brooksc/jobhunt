---
id: TASK-661
title: >-
  Model evaluation must measure consistency, and must stop drawing conclusions
  from single samples
status: Done
assignee: []
created_date: '2026-08-05 18:12'
updated_date: '2026-08-09 22:26'
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
- [x] #1 Every eval runs N repeats per model and reports a pass rate with variance, not a single pass/fail
- [x] #2 Consistency (verdict flips and score spread across identical calls) is recorded alongside accuracy for every candidate
- [x] #3 A model is only recommended when both its accuracy AND its consistency are measured over repeats
- [ ] #4 not verified (environment): local models are measured on the same two axes — LM Studio was not running and starting it is a UI action, which is out of scope for this run
- [x] #5 marketing/help/which-model.html is regenerated from the committed results
- [x] #6 The recommendation is re-decided on this evidence
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

**Measured 2026-08-06. The headline finding is that our evaluation method was unsound, not just incomplete.**

**1. Scores are not reproducible.** The same job, résumé, model and code scored **37, 33, then 2**. Extraction was identical across runs (same 15 requirement texts), the prompt builder is deterministic, and both calls used `json_schema` — the variance is entirely in the model's judgement. 5 of 15 verdicts flipped, all toward pessimism.

**2. Confirmed by isolating the model.** Byte-identical payload (sha256 verified), `temperature: 0`, sent repeatedly straight to the API:

| Model | Verdicts changed | Penalty spread | Served by |
|---|---|---|---|
| `anthropic/claude-haiku-4.5` | **0 / 15** (8 runs) | **0.0** | Amazon Bedrock |
| `mistralai/ministral-14b-2512` | 2 / 15 | 1.5 | Mistral (first-party) |
| `microsoft/phi-4` | 3 / 15 | 4.5 | DeepInfra |
| `google/gemini-3.5-flash-lite` | 5 / 15 | 10.4 | Google |
| `anthropic/claude-sonnet-5` | 6 / 15 | 12.6 | Amazon Bedrock |
| `deepseek/deepseek-v4-flash` | 7–8 / 15 | 10.4–15.6 | **five different providers across eight calls** |
| `qwen/qwen3.5-27b` | unusable | — | paraphrased requirements differently each run |

**3. Architecture is not the discriminator.** Dense-vs-MoE did not predict stability: Haiku and Sonnet 5 are both Anthropic on Bedrock and sit at opposite ends. Capability didn't either — Sonnet 5 is *less* stable than Haiku. What tracked was the specific model-plus-serving-stack.

**4. Pinning the provider does not fix it.** With `provider.order` set and `allow_fallbacks: false`, deepseek still flipped 5–9 of 15 per provider (Parasail 6, AtlasCloud 9, SiliconFlow 5). Pinning also produced sustained 429s — it trades availability for a stability gain that doesn't materialise.

**5. This invalidates single-sample benchmarking.** `OverCreditEval` now **fails for deepseek, Haiku and Ministral alike**, on the same two cases (CUDA, PCI). The previously-recorded "deepseek 7/7" was `FitScoringEval` only, and on a model that doesn't answer the same way twice it was probably a lucky draw.

**Required change of method:** every eval must run **N repeats per model** and report a pass *rate* with variance, never a single pass/fail. A benchmark that can't distinguish a good model from a lucky sample is worse than none, because it gets published — which it was.

The public page has been corrected (commit `0561b987`): recommendation marked under review, the 7/7 claim qualified, and a consistency table added.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
New `ConsistencyEval` scores one fixed posting repeatedly through the app's own scoring path and reports score spread, standard deviation, and how many requirement verdicts changed answer. `OverCreditEval` and `FitScoringEval` already had repeat support; this adds the axis none of them measured.

**Measured (6 requested repeats each, byte-identical input, temperature 0):**

| Model | Usable | Scores | sd | Spread | Verdicts changed |
|---|---|---|---|---|---|
| Claude Haiku 4.5 | 4 | 73, 69, 65, 72 | 3.1 | **8** | 1 of 7 |
| Ministral 14B | 5 | 67, 67, 62, 81, 72 | 6.4 | **19** | 1 of 7 |

**The re-decision (criterion 6): the ordering survives, the magnitudes do not.** The page claimed 0 points of swing for Haiku and ~2 for Ministral. Haiku is still the steadier by roughly a factor of two, so the existing recommendation stands — but neither model is near-deterministic, and a score moving 8 to 19 points between identical requests is more than enough to reorder a list around a threshold. I deliberately did **not** crown a different model: 4–5 samples on one posting is enough to disprove "~2 points" (one 19-point swing does that) and not enough to rank models precisely. The page now says exactly that, including the sample size.

This corroborates the 41–53 spread I saw across six walkthrough recordings, which was the original reason to doubt the claim.

**Incidental finding, affecting both models:** 2–4 of every 6–8 requests returned an empty `content` and were discarded. Aggregator-level rather than model-level; the app retries, so users experience it as slowness rather than error. Recorded on the page.

**Two mistakes of mine, both of which produced confident wrong numbers:**

1. The first three-model OverCredit run ignored `JOBHUNT_EVAL_*` entirely — `xcodebuild` only forwards `TEST_RUNNER_`-prefixed variables — so it measured one model three times. Now documented in `EvalProvider`.
2. The verdict tracker filtered on the *requested* repeat count, so any failed pass dropped every requirement and the run printed "0 of 0 requirements changed answer" — indistinguishable from perfect stability, and the exact opposite of the data.

Criterion 4 is `not verified`: LM Studio was not running and starting it is a UI action, out of scope for this run.
<!-- SECTION:FINAL_SUMMARY:END -->
