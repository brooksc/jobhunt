---
id: TASK-709
title: >-
  Fit rubric v4: domain_fit judges the role not the employer, experience_level
  becomes two-sided, add a function-and-audience rule
status: To Do
assignee: []
created_date: '2026-08-31 21:04'
labels: []
dependencies: []
priority: high
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
