---
id: TASK-709
title: >-
  Fit rubric v4: domain_fit judges the role not the employer, experience_level
  becomes two-sided, add a function-and-audience rule
status: On Hold
assignee: []
created_date: '2026-08-31 21:04'
updated_date: '2026-08-31 21:38'
labels: []
dependencies: []
priority: low
type: enhancement
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From `docs/ai-prompts-review-2026-08-31.md` §1, §2, §3. **These must ship together as one `assessment_prompt_version` bump to v4.** Landing them separately would create v4, v5 and v6 — three more mutually incomparable score populations on top of the v1/v3 split already in the store (see [[TASK-710]]).

## §1 — `domain_fit` points at the employer, not the role (the largest defect)

Current definition ends "…the field the company operates in and the kind of thing it builds", which sends the model to the **employer** rather than the **work**.

The evidence is self-refuting, from two postings at one company, same résumé, same prompt version, minutes apart:

- Job **1108**, Senior Program Manager, Enterprise Technology & AI — a CIO-org role running internal business systems. `domain_fit` **90**, rationale citing "developer platforms, AI infrastructure… aligning closely with GitLab's product and operational domain." True about the company, irrelevant to the job.
- Job **777**, Principal Product Manager, AI Software Factory — the actual product role, where the candidate contributes to an open-source coding agent. `domain_fit` **85**, *penalised* for not matching the employer's product closely enough.

So the internal-IT role was rewarded for matching a product it has nothing to do with, and the product role was penalised against the same phrase. Overall: 1108 scored **94**, 777 scored **90** — the rubric ranked the role the candidate cannot do above the one they are unusually suited to.

This is systematic, not a one-off: every employer has roles whose domain is unrelated to its product (corporate IT, finance ops, trust and safety, workplace, GTM ops), and all of them inherit the product's domain score under the current wording.

Replacement wording is in the review, §1. Cost ~90 prompt tokens.

## §2 — `experience_level` is one-sided, which is why it looks dead

It averages 90 across 872 v3 scores with 54% exactly 95. The earlier reading (in `docs/fit-scoring.md` §10.3) was that the dimension carries no signal and its weight should be redistributed. **The review argues, convincingly, that it is degenerate because the definition is one-directional** — "alignment" is symmetric in English, but every stored rationale treats exceeding the bar as satisfying it. A 22-year principal against a 2–3 year posting scored **85** ("substantially exceeds"); the same résumé against a Senior posting scored **95**.

A dimension that only measures a floor reads near-constant for any experienced candidate. That is a property of the wording, not evidence the axis is useless — and over-levelling is a real, common rejection cause that a résumé and posting jointly determine with high confidence.

**Fix the definition and re-measure before deleting anything.** If it stays degenerate, the deletion argument then rests on evidence about the right question. Replacement wording in the review, §2. Zero token cost.

## §3 — no counterpart to the NAMED-TECHNOLOGY RULE for function or audience

The named-technology rule is the strongest thing in the fit prompt and stops exactly this class of adjacency inflation. Nothing equivalent exists for the *function* a role sits in or the *users* it serves, which generalise just as wrongly: running an external developer platform is not running internal enterprise IT; security compliance is not security engineering.

Job 1108's assessments show it — "Familiarity with Enterprise Tech domains such as business systems, data, AI, security, infrastructure, or enterprise architecture" scored `met` on evidence about GPU clusters and API platforms, when the posting's emphasis for a CIO-org role is business systems and enterprise architecture, both absent. v3's ALTERNATIVES RULE should have fired and didn't.

Proposed rule text in the review, §3. ~70 tokens.

## Sequencing

Benchmark first — see [[TASK-709]]. **1108 above 777 is the ready-made regression case**: the correct outcome is 777 ranked higher. Do not ship on reasoning alone; all three changes are untested, and the review says so plainly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All three prompt changes land in a single assessment_prompt_version bump to v4
- [ ] #2 domain_fit scores the role's work, audience and constraining industry — not the employer's product line
- [ ] #3 experience_level scores down for materially exceeding the role's level as well as falling short
- [ ] #4 A function-and-audience rule sits beside the named-technology rule
- [ ] #5 Job 777 ranks above job 1108 after the change, verified by an eval run
- [ ] #6 The experience_level distribution is re-measured after the definition change, before any decision to remove the dimension
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: primary
created: 2026-08-31 21:38
---
**Benchmarked 2026-08-31 ([[TASK-710]], `scratchpad/bench-fit.md`, 550 calls, $9.17). Three NO-GOs. Do not ship this as written.**

| change | verdict | evidence |
|---|---|---|
| §1 `domain_fit` → role's work | **NO-GO** | internal roles +1.5 vs product roles +1.8 — no differential at all, `domain_fit` simply rises across the board, inversion untouched |
| §2 `experience_level` two-sided | **diagnosis GO, wording NO-GO** | it does what it claims — the 95-pile drops 65%→15%, σ 8.2→19.1 — but the inversion *worsens* from −3.2 to −12.3 |
| §3 FUNCTION AND AUDIENCE RULE | **NO-GO** | mean |Δ| 2.21, below the noise floor; 0 of 5 fixture verdicts changed |
| all three together | **NO-GO** | inversion still unfixed (−1.3) |

**The gating number is run-to-run variance: σ = 3.16, mean spread 7.6 points over five identical runs. 21 of 29 jobs move ≥4 points on repeat scoring alone.** So any argument of the form "job A at 94 beats job B at 90, therefore the rubric is broken" is, in general, reading noise — and that includes the review's framing.

**But the review's specific pair survives, for a reason it did not establish.** Jobs 1108 and 777 are unusually *stable* items (σ 0.9 and 1.5 against a corpus mean of 3.16), and 1108 outscored 777 in **5 of 5** runs (93.6 ± 0.9 vs 90.4 ± 1.5, ~4 standard errors). The inversion is real and reproducible; the *magnitude* argument is not. Credit where due — the finding holds, the reasoning behind it doesn't.

**Consequence for versioning:** shipping §1 or §3 would make 872 stored v3 scores incomparable in exchange for no measured behaviour change. That is a pure loss. §2 is the only change that earns a version bump, and not with this wording, since it makes the one case it was meant to help substantially worse.

**What survives:** §2's *diagnosis* — `experience_level` is degenerate because the definition is one-sided, not because the axis carries no signal. That is now measured, and it settles the open question in `docs/fit-scoring.md` §10.3: **do not delete the dimension.** A better two-sided wording, one that spreads the distribution without inverting the pair further, is worth a second attempt.

Parked at Low rather than closed: the underlying observation about `domain_fit`'s referent may still be correct and simply not reachable through prompt wording alone. Re-open only with a hypothesis that clears ~3 points of per-job noise.
---
<!-- COMMENTS:END -->
