---
id: TASK-662
title: >-
  Marketing page: "Which AI model should I use?" — recommendation, what we
  tested, and real costs
status: Done
assignee: []
created_date: '2026-08-05 18:12'
updated_date: '2026-08-05 19:30'
labels:
  - marketing
  - docs
  - onboarding
dependencies:
  - TASK-661
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Choosing a model is the hardest decision JobHunt asks of a new user, and right now every user has to repeat the evaluation work from scratch — pick a provider, guess a model, and have no idea whether the output is any good or what it will cost. We already did that work. It isn't written down anywhere a user can find.

**Add a page to the static site in `marketing/`** (alongside `index.html`, `privacy.html`, `help/index.html`, `help/faq.html`), discoverable from the help section.

**Content**

1. **Lead with one recommendation, and let people stop reading.** Most users want to be told. Name the model, the provider, roughly what it costs for a typical month of job hunting, and how to set it up — before any comparison table.
2. **What else was tested and why it wasn't chosen.** Measured results only (see [TASK-661]); nothing may be listed as tested if it hasn't been. Include the *kind* of failure, not just a score — `gemini-3.1-flash-lite` regressed when the prompt grew, which is more useful to a reader than "5/7".
3. **Cost table grounded in real token counts**, expressed the way a user thinks: *"100 job postings scored ≈ $X"*, not dollars per million tokens. `CostEstimator` already produces per-corpus token estimates (the AI settings pane shows them for the current corpus), so the numbers should come from measurement.
4. **The free option, honestly.** A local model via LM Studio or Ollama costs nothing and never sends a posting off the machine, at some cost in accuracy and speed. Say what that cost is rather than implying local is free of tradeoffs.
5. **Two ways to reach the same model.** DeepSeek is available via OpenRouter *or* the DeepSeek API directly — different keys, pricing and signup. Explain when each makes sense. (Direct DeepSeek isn't a first-class provider yet — [TASK-664].)
6. **Say it can be changed later**, and that changing it doesn't rescore existing jobs unless asked. Lowers the stakes of the decision.

**Keep it current.** Model pricing and lineups move fast; a stale recommendation is worse than none. Date the page, say which app version the testing was done against, and prefer generating the table from the committed eval results ([TASK-661]) over hand-maintained numbers.

Linked from onboarding and Settings by [TASK-663].
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A page exists under marketing/ and is reachable from the help section
- [x] #2 It opens with a single named recommendation and setup steps, before any comparison
- [x] #3 Every model presented as tested has a measured result from TASK-661
- [x] #4 Costs are expressed per N job postings, derived from measured token counts
- [x] #5 The local/free option is covered with its actual tradeoffs stated
- [x] #6 Both OpenRouter and direct DeepSeek routes are explained
- [x] #7 The page carries a date and the app version the testing was done against
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped `marketing/help/which-model.html`, linked from the help TOC, the Settings Reference and the Fit Scoring explanation.

**Recommendation up front:** DeepSeek V4 Flash via OpenRouter, ~9¢ per 100 postings, with four setup steps — so a reader who just wants to be told can stop after the first box.

**Only measured claims.** Just the two benchmarked models are presented as tested (DeepSeek 7/7, Gemini 3.1 Flash Lite 5/7). Gemini 3.5 Flash Lite, Claude Haiku 4.5 and Claude Sonnet 5 appear in the cost table marked "—" and are explicitly called out as untested. Local models are recommended for privacy with the honest caveat that we have not benchmarked them, so we cannot say what accuracy they cost.

**Costs are derived, not guessed:** ~5,522 input / 450 output tokens per job (from the app's own Cost Estimate over a real corpus) × live OpenRouter prices, expressed per 100 and per 500 postings.

| Model | 100 jobs | 500 jobs |
|---|---|---|
| DeepSeek V4 Flash | $0.09 | $0.45 |
| Gemini 3.1 Flash Lite | $0.21 | $1.03 |
| Gemini 3.5 Flash Lite | $0.28 | $1.39 |
| Claude Haiku 4.5 | $0.78 | $3.89 |
| Claude Sonnet 5 | $1.55 | $7.77 |

Also covers the OpenRouter-vs-direct-DeepSeek choice (with the honesty that direct currently means the generic Custom provider and no cost estimate — TASK-664), what data leaves the machine, and that the choice is reversible.

Dated and version-stamped ("benchmarked against JobHunt 1.3.0, August 2026") with an invitation to report staleness, since a stale recommendation carrying our authority is worse than none.

**Also fixed en route:** the Settings Reference recommended "Gemini Flash is a good cost/quality default" — contradicted by our own benchmark. Now points at the page.

Remaining: fill in the untested rows via TASK-661, and surface the page from onboarding and Settings via TASK-663.
<!-- SECTION:FINAL_SUMMARY:END -->
