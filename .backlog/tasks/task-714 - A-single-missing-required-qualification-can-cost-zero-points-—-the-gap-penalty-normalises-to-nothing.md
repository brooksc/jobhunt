---
id: TASK-714
title: >-
  A single missing required qualification can cost zero points — the gap penalty
  normalises to nothing
status: To Do
assignee: []
created_date: '2026-08-31 22:15'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 98000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found 2026-08-31 while wiring scoring feedback into the queue ([[TASK-707]]). The agent's first test asserted that applying a `neverCredit` correction would *lower* the score. It failed — and the reason is worth investigating on its own.

The correction worked: the requirement was demoted, `penaltyReasons` and `requirements_not_met` were populated. But with a single requirement in play, `FitScorer.computeScore`'s gap penalty is **normalised by the number of requirements the posting listed**, so the penalty rounded to **0**. The job kept its score while carrying a recorded, confirmed missing required qualification.

The test now asserts the recorded gap rather than the score, which is the right observable for proving the wiring. But the underlying behaviour looks wrong: **a confirmed missing *required* qualification costing zero points** is hard to justify, and it is the same normalisation that `docs/ai-prompts-review-2026-08-31.md` §5 identifies from the other direction — a posting listing eight easy requirements generates no penalties and scores near the ceiling, while a demanding posting that stretches the candidate scores lower.

So the normalisation has two failure modes at opposite ends:

- **Few requirements** — each gap is divided by a small denominator but apparently still rounds away; a single miss costs nothing.
- **Many easy requirements** — gaps are diluted; the corpus already contains a part-time hourly role scoring 99.

Worth checking before changing anything: how many postings in the store have few enough requirements for this to bite, and whether the rounding or the normalisation is the actual culprit. This may be a rounding bug with a one-line fix rather than a design problem.

**Do not tune this by feel.** Run-to-run variance is σ = 3.16 ([[TASK-713]]), so any adjustment must clear ~3 points per job to be distinguishable from noise, and it must be measured against the 20-job hand-labelled corpus at `~/Desktop/resume/fitscore-collab/labelled` (561 requirement-level verdicts), which `ScoreLab --labelled` reads. A change here alters what every score means, so it needs an `assessment_prompt_version` bump only if the prompt changes — arithmetic-only changes do not, but they do make stored scores incomparable in a way the version field will not record. Decide how to handle that before shipping.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 It is established whether the zero-cost single gap is a rounding artefact or the normalisation working as designed
- [ ] #2 The number of stored jobs with few enough requirements for this to bite is measured
- [ ] #3 Any change is validated against the 20-job labelled corpus, not by inspection
- [ ] #4 Any score movement is shown to exceed the σ = 3.16 noise floor
- [ ] #5 A decision is recorded on how arithmetic-only changes affect comparability with stored scores
<!-- AC:END -->
