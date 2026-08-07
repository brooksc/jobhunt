---
id: TASK-669
title: Expand fit-scoring ground truth and attack partial→met over-crediting
status: To Do
assignee: []
created_date: '2026-08-07 16:56'
labels:
  - scoring
  - eval
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The scoring arithmetic is done. Measured through `ScoreLab --labelled`, the shipped arithmetic reproduces ground truth to **MAE 4.9, rho +0.968, 4 of the top 5** *given correct per-requirement verdicts*. That is inside the ±5 the user asked for. Every remaining point of error is verdict error.

## Why more testing, specifically

Three deterministic fixes have now been measured against the 20 hand-labelled jobs. All three had sound *detection*; only one helped.

| fix | detection | acting on it |
|---|---|---|
| non-discriminating requirements | sound | helps |
| fragment extraction | 15/18 agreement with the labeller | score-neutral — P1 got there first |
| fabricated evidence | 76% lifted-from-posting vs the measured 74% | actively harmful — 6 of 7 demotions contradicted the labeller |

The evidence-demotion rule was refuted on a subset of **7 rows**. A decision that thin could have gone the other way on noise, and the fragment call rested on 18. The ground-truth set is too small for the ship/no-ship calls being made against it.

## Work

1. **Second labelling batch, blind.** Ask the résumé agent for ~20 more jobs through `scripts/export-fit-analysis.py --blind`, which withholds `current_score`, `dimensions` and per-requirement `status`/`evidence`. The first batch's overall bands were anchored to the model's own output (measured: hand bands sat at MAE 7.6 from the dimension base vs 11.4 for bands re-derived from the same agent's verdicts). The first batch's *verdicts* remain valid; its *bands* do not.
2. **Attack `partial → met`.** It is the single most common defect (21 instances), and over-crediting is concentrated in the **top quartile** — 9 over-credited, 0 under — which is exactly the error that damages the stack-rank the user triages from. Tighten what qualifies as `met` in the scoring prompt.
3. **Measure before shipping, not after.** A prompt change can't be validated by re-scoring stored JSON — it needs fresh LLM calls over the labelled set. Cheap on ministral-14b. Two of the last three "obviously correct" fixes failed this gate.

## Notes

- Harness: `ScoreLab --labelled <dir> [--resume <path>]`, which scores through the app's own `FitScorer`, so anything it endorses is what ships.
- Labels live at `~/Desktop/resume/fitscore-collab/labelled/` — outside the repo, because they quote résumé facts and this repo is public.
- Related: TASK-661 (thorough model evaluation with repeats).
- If top-of-list ordering still feels wrong after the `met`-threshold work, the next honest step is a different model for the verdicts themselves, not more post-processing of this one's output.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A second blind labelling batch (~20 jobs) exists and its bands are set without sight of the model's score
- [ ] #2 The `met` threshold change is measured over the labelled set with fresh LLM calls, before it ships
- [ ] #3 Top-5 overlap with ground truth is reported before and after; the change ships only if it does not regress
- [ ] #4 `partial → met` instance count is re-measured after the change
<!-- AC:END -->
