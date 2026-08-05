---
id: TASK-662
title: >-
  Marketing page: "Which AI model should I use?" — recommendation, what we
  tested, and real costs
status: To Do
assignee: []
created_date: '2026-08-05 18:12'
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
5. **Two ways to reach the same model.** DeepSeek is available via OpenRouter *or* the DeepSeek API directly — different keys, pricing and signup. Explain when each makes sense. (Direct DeepSeek isn't a first-class provider yet — [TASK-663].)
6. **Say it can be changed later**, and that changing it doesn't rescore existing jobs unless asked. Lowers the stakes of the decision.

**Keep it current.** Model pricing and lineups move fast; a stale recommendation is worse than none. Date the page, say which app version the testing was done against, and prefer generating the table from the committed eval results ([TASK-661]) over hand-maintained numbers.

Linked from onboarding and Settings by [TASK-662].
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A page exists under marketing/ and is reachable from the help section
- [ ] #2 It opens with a single named recommendation and setup steps, before any comparison
- [ ] #3 Every model presented as tested has a measured result from TASK-661
- [ ] #4 Costs are expressed per N job postings, derived from measured token counts
- [ ] #5 The local/free option is covered with its actual tradeoffs stated
- [ ] #6 Both OpenRouter and direct DeepSeek routes are explained
- [ ] #7 The page carries a date and the app version the testing was done against
<!-- AC:END -->
