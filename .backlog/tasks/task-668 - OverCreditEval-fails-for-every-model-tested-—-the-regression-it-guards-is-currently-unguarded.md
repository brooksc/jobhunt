---
id: TASK-668
title: >-
  OverCreditEval fails for every model tested — the regression it guards is
  currently unguarded
status: To Do
assignee: []
created_date: '2026-08-07 00:23'
labels:
  - llm-eval
  - fit-scoring
dependencies:
  - TASK-661
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`OverCreditEval.testAdjacentEvidenceIsNotScoredAsMet` fails identically on **every** model tried on 2026-08-06:

| Model | FitScoringEval | OverCreditEval |
|---|---|---|
| `deepseek/deepseek-v4-flash` | passed | **failed** |
| `anthropic/claude-haiku-4.5` | passed | **failed** |
| `mistralai/ministral-14b-2512` | passed | **failed** |

Same two cases each time:

```
Akamai #607   — GPU migration is not CUDA expertise: evidence asserts CUDA, which the résumé never states
Pinterest #619 — FTC/DSA compliance is not PCI:   evidence asserts PCI,  which the résumé never states
```

These are the two original over-credit reports the NAMED-TECHNOLOGY RULE in prompt v3 was written to prevent. If no candidate model passes them, then **the guard is currently providing no protection** — a scorer can assert CUDA experience the résumé never mentions and nothing catches it.

**Three possibilities, and they need separating before anyone acts:**

1. **The rule isn't working.** Prompt v3's named-technology rule may be too buried, or worded in a way models don't apply to the *evidence* field (the failure is that the evidence text asserts the technology, not necessarily that `status` is wrong).
2. **The assertion is too strict.** It appears to check whether the evidence string mentions the named technology. A model can legitimately write "no CUDA experience found" — which mentions CUDA while making the correct judgement. If the check is a substring match, it may be failing correct answers. **Check this first**; it is the cheapest to rule out and would mean the eval, not the models, is broken.
3. **It's flaky.** Given TASK-661's finding that verdicts flip on 5–9 of 15 requirements between identical calls, a single-sample pass/fail may simply be sampling noise. The earlier "deepseek 7/7" may have included a lucky pass here.

Distinguishing (2) from (1) and (3) is the whole job: read the assertion, then run it N times per model and report a pass *rate*.

**Do not "fix" this by loosening the prompt.** Adding a broad rule to the scoring prompt has already measurably regressed scoring once (job #231 went from a correct 60 back to 96 on `gemini-3.1-flash-lite`). Any prompt change must be validated across repeats, on more than one model.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 It is established whether the assertion itself is at fault (e.g. substring-matching a technology name that a correct negative answer legitimately contains)
- [ ] #2 OverCreditEval is run N times per model and reported as a pass rate, not a single pass/fail
- [ ] #3 If the guard is genuinely unenforced, the named-technology rule is revalidated across repeats and more than one model
- [ ] #4 No prompt change is made without measuring it across repeats against the existing fixtures
<!-- AC:END -->
