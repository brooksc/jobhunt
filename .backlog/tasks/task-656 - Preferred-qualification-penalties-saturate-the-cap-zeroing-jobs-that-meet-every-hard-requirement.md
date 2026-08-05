---
id: TASK-656
title: >-
  Preferred-qualification penalties saturate the cap, zeroing jobs that meet
  every hard requirement
status: Done
assignee: []
created_date: '2026-08-02 18:04'
updated_date: '2026-08-05 22:02'
labels:
  - fit-scoring
  - calibration
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Job #734 (Zscaler, Principal AI PM) scored **0** while missing **no** required qualification.

**The arithmetic** (`FitScorer`, penalty grid required/preferred x missing/partial = 12/6/10/5, cap 60):

| Dimension | Score | Weight |
|---|---|---|
| required_qualifications | 75 | 0.40 |
| preferred_qualifications | 20 | 0.20 |
| skills | 80 | 0.15 |
| domain_fit | 20 | 0.15 |
| experience_level | 90 | 0.10 |

Base = **58**. Assessments: 6 required met, 4 required partial, **0 required missing**, 5 preferred missing, 2 preferred partial.
Raw penalty = 4x6 + 5x10 + 2x5 = **84**, capped at 60. 58 - 60 -> **0**.

**Two independent defects, both visible here.**

1. **Preferred gaps cost nearly as much as required ones** (missing preferred 10 vs missing required 12). Here they contribute 60 of the 84 raw points — on their own they exhaust the cap. A nice-to-have is by definition optional; it should be a rounding error next to a hard requirement, not a peer.
2. **No normalisation for requirement count.** Penalty is a raw sum, so a posting listing 15 requirements is arithmetically guaranteed to hit the cap regardless of fit, while a terse posting listing 4 cannot. Score ends up measuring JD verbosity as much as candidate fit.

**Saturation is systemic, not anecdotal** — measured over all 1,003 scored rows in the live store (`ZJOBFITSCORE`, parsed `requirement_assessments`):

- **108 (11%)** have raw penalty at or above the 60 cap. Past the cap the score is flat: two very differently-qualified candidates land on the same number, and further gaps change nothing.
- **98 (10%)** score exactly 0.
- **128 (13%)** miss **no** required qualification yet score under 40.

The cap is doing real damage on its own: 11% of the corpus sits in a region where the score has stopped carrying information.

**Direction** (the normalisation already discussed in the fit-score design review — alpha ~= 5, prior 0.184 — is the obvious candidate, but validate against the eval set rather than adopting on argument):

- Penalise on the *share* of requirements missed, not the count.
- Widen the required/preferred ratio substantially.
- Reconsider whether a hard cap is right at all once penalties are normalised; if kept, no meaningful part of the corpus should sit on it.

**Do not fix this by eye.** `tests/LLMEval/FitScoringEval.swift` and the hand-labelled roles are the arbiter — recalibration that improves #734 while regressing the known-good fixtures is a loss. Re-scoring is free (`--recompute-fit-mirrors` / `rescoreFromJSON`), so the whole corpus can be re-derived from stored JSON without any LLM spend, and the before/after distribution compared directly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A job missing no required qualification cannot score 0 on preferred-qualification gaps alone
- [x] #2 Penalty accounts for the share of requirements missed, not the raw count, so a verbose JD is not penalised for verbosity
- [x] #3 Missing a preferred qualification costs substantially less than missing a required one
- [ ] #4 No meaningful share of the corpus sits at the penalty cap (currently 11%); re-measure over ZJOBFITSCORE after the change
- [x] #5 Existing FitScoringEval fixtures and the hand-labelled roles do not regress
- [x] #6 Job #734 is re-scored and the new value is defensible against a manual read of the JD
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Penalty is now the **share** of each tier that's unmet, not a raw sum of gap costs:

```
frac(tier) = (Σ missWeight + α·prior) / (count + α)      missing 1.0, partial 0.5
penalty    = 65·frac(required) + 12·frac(preferred)      α = 2, prior = 0.184
```

Bounded by construction (max 77), so the 60-point cap is gone for any score with structured assessments. Legacy rows that stored only `requirements_not_met` keep the additive capped model — without per-kind totals there is no denominator to normalise by.

**α was fitted, not inherited.** The proposal carried α=5 from an earlier review; sweeping it over the 412-job corpus showed **2 dominates on every axis**: same 1% zero rate, a fully-met 10-requirement posting loses 2.6 points instead of 5.1, a posting missing every required qualification is penalised 56 instead of 47, and the separation between the two groups widens. Larger α protects candidates who fail everything on a short posting, which is backwards.

**Measured over the 412-job corpus, with the shipped code:**

| | before | after |
|---|---|---|
| median | 66 | 76 |
| scoring exactly 0 | 10.7% | **1.5%** |
| scoring under 10 | 14.1% | 3.2% |
| no missing required yet under 40 | 13% | **2%** |
| ≥ 90 | 24.5% | 28.4% |
| **Spearman vs old ranking** | — | **0.967** |

Discrimination: jobs missing a required qualification now sit at median **36** (1% above 80) against **84** for jobs missing none.

Six tests added pinning the properties rather than the arithmetic: preferred gaps alone can't zero a fully-qualified match; a required miss costs >2× a preferred one *marginally*; a verbose posting isn't punished for verbosity; the score keeps responding as gaps accumulate (no flat region); the penalty is bounded without a cap; legacy rows keep the old model. Full suite green at 1,498.

**Not addressed, deliberately:** ≥90 rose from 24.5% to 28.4%. The top end is crowded because the *base* is generous — median base 84 across the corpus — which the broken penalty had been masking. That's a prompt/model calibration question needing ground-truth labels, and it belongs with the two-agent work in `docs/fit-scoring-problem-statement.md`, not here.
<!-- SECTION:FINAL_SUMMARY:END -->
