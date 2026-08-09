---
id: TASK-669
title: Fit-scoring error direction measured — the partial→met premise was backwards
status: Done
assignee: []
created_date: '2026-08-07 16:56'
updated_date: '2026-08-09 22:28'
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
- [ ] #1 not done (PARK d): a second blind labelling batch — the résumé agent owns the labelling, and this run cannot produce it
- [ ] #2 not done (contraindicated): the `met` threshold change was NOT made, because measurement showed the premise inverted — see the final summary
- [ ] #3 not done (contraindicated): top-5 overlap before/after was not measured, because no change was made
- [x] #4 The error direction is measured over the labelled set and the `partial → met` count is correctly interpreted
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
**The premise was backwards, and acting on it would have made scoring worse.**

I filed this task myself, reading "21 × `partial → met`" as the dominant over-crediting defect and proposing to tighten what qualifies as `met`. The labels use `model → truth`, so `partial → met` is the model saying *partial* where the truth is *met* — the model being too **harsh**. The labeller's notes on those very rows read "UNDER-credit", with reasons ("API review automation 92→5 days … is exactly this").

Cross-tabulated over all **212** labelled assessments with a usable ground truth:

| | count | share |
|---|---|---|
| agree | 165 | 79% |
| over-credit (model more generous) | 20 | 10% |
| under-credit (model harsher) | 25 | 12% |

The errors are near-balanced, tilting *harsh*. The single largest cell is `partial → met` at 21 — all under-credit. Tightening the `met` threshold would have pushed the more common error further in the wrong direction, on a scorer that already agrees with the labeller 79% of the time.

**So no prompt change was made**, and criteria 2 and 3 are marked not-done rather than quietly satisfied. Committed `scripts/label-error-direction.py` so the direction is re-derivable rather than remembered — it needs no LLM calls.

**A second, independent reason not to attempt the threshold work now.** TASK-661 measured the same posting scoring 62–81 across identical calls (Ministral, spread 19; Haiku, spread 8). A prompt change worth a few points cannot be validated against that noise without many repeats per job, and 20 jobs × repeats is hours of wall-clock at the observed throughput. Any future threshold work should follow a steadier model, not precede it.

**What remains, for whoever picks this up:** the blind second labelling batch is PARK(d) — the résumé agent owns labelling. If a threshold change is ever attempted it should aim at the 12 `met → partial` over-credits without disturbing the 21 under-credits, which is a much narrower target than "tighten `met`", and it must be measured with repeats.
<!-- SECTION:FINAL_SUMMARY:END -->
