---
id: TASK-650
title: 'Normalize seniority: 55 distinct free-text values are polluting fit scoring'
status: Done
assignee: []
created_date: '2026-07-26 20:23'
updated_date: '2026-08-09 20:25'
labels:
  - llm
  - data-quality
  - extraction
  - fit-scoring
dependencies: []
references:
  - core/LLM/PromptBuilder.swift
  - core/LLM/Normalization.swift
  - core/Models/Job.swift
  - tools/migrator/Args.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`Job.seniority` is stored as free text with no enum constraint and no normalization, unlike `remote_type` which the prompt restricts to four values (`PromptBuilder:96`). The extraction prompt only says `seniority: string or null` (`PromptBuilder:104`), so the model returns whatever the posting used.

Live store: **55 distinct values across 415 non-null jobs**, including pure case duplicates and free-form experience ranges:

    Senior 134 · Staff 47 · senior 42 · Principal 42 · Lead 18 · Senior level 17
    mid-level 14 · Director 11 · mid-senior 10 · Senior/Principal 5 · Manager 5
    experienced 4 · III 4 · principal 3 · mid_senior 3 · Mid level 3 · staff 2
    ... "5+ years", "7+ years of experience", "10–15+ years", "II", "AVP"

`Senior`/`senior`, `Staff`/`staff`, `Principal`/`principal` and five spellings of mid-level are the same thing stored repeatedly.

**Why this is more than cosmetic:** seniority is injected into the fit-scoring prompt (`PromptBuilder:205`, under the `experience_level` dimension — "alignment between the candidate's seniority/years and the role's level"). Inconsistent and sometimes meaningless values ("III", "5+ years") are feeding the scorer right now, so this is plausibly degrading fit scores across the library, not just blocking a future filter.

Fix shape, mirroring what `remote_type` already gets: constrain the prompt to an enum, add a normalizer for existing/legacy values (in the spirit of `RemoteTypeInferer`), and a migrator mode to backfill stored rows. Only once values are stable is a seniority filter or grouping meaningful — a filter built on today's data would silently miss 42 lowercase "senior" jobs.

Open question worth deciding first: the right enum. Something like intern / entry / mid / senior / staff / principal / director / vp+ — with a rule for mapping bare year-ranges, or dropping them to null rather than guessing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The extraction prompt constrains seniority to a documented enum, as remote_type already is
- [x] #2 A pure, unit-tested normalizer maps legacy free-text values (case variants, mid_senior/mid-level spellings, Sr./III) onto the enum
- [x] #3 Values that carry no reliable level signal (bare year ranges) normalize to null rather than being guessed into a band
- [x] #4 A migrator mode backfills stored seniority for existing jobs, and is idempotent
- [x] #5 Fit-scoring prompts receive the normalized value
- [ ] #6 not verified (needs the live store): distinct stored values drop from 55 to the enum's size plus null — proven on synthetic data (8 values collapse to 3) and idempotent, but the real 415-job store was not touched, since that needs the app quit and a backup, which is the user's call
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
**The enum, which the task left open.** intern / entry / mid / senior / lead / staff / principal / manager / director / executive. Both tracks are represented because postings use both, and folding `Director` into `Principal` would erase the distinction the user is actually triaging on. `lead` is included over the task's sketch because the live store has 18 of them.

**Bare years and ordinals normalize to null, not a band.** "5+ years" maps to different levels by company and industry, and "III" has no scale attached. Since this text feeds `experience_level` scoring, guessing a band would push fabricated evidence into the score — worse than the honest absence the scorer already handles.

**A compound takes its lower bound** (`Senior/Principal` → `senior`): that is the level the posting will actually consider, and overstating it inflates the fit of roles the candidate is under-levelled for.

Applied in three places, because one is not enough: the prompt now constrains the value the way `remote_type` already does; the write path normalizes again (the model still returns the posting's own wording often enough); and `--normalize-seniority` backfills stored rows. The backfill is idempotent because every canonical value is a fixed point of the normalizer — asserted directly over `SeniorityLevel.allCases`.

**Tests** (15): case variants collapse; five mid-level spellings collapse; abbreviations (`Sr.`, `Jr`); unusable values clear to null; compounds take the first level; the management track stays distinct; longer phrases beat their prefixes (`Senior Manager` is a manager, not a senior IC); no substring false positives (`seniority`, `vpn`); and four store-level tests covering collapse, clearing, idempotency and canonical rows being left untouched.

Criterion 6 is `not verified`: the collapse is proven on synthetic data and by construction, but the real 415-job store was not touched — that needs the app quit and a backup first, which is the user's call.
<!-- SECTION:FINAL_SUMMARY:END -->
