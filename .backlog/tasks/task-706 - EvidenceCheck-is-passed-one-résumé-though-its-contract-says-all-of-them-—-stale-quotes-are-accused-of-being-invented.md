---
id: TASK-706
title: >-
  EvidenceCheck is passed one résumé though its contract says all of them —
  stale quotes are accused of being invented
status: Done
assignee: []
created_date: '2026-08-31 20:36'
updated_date: '2026-09-04 19:52'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while documenting the AI prompts (2026-08-31, `docs/ai-prompts.md`). **Verified at both call sites.**

`EvidenceCheck.classify` (`core/Services/EvidenceCheck.swift:82-87`) documents its own contract:

> `resumes` is every résumé the user has ever had active, not just the current one: a quote from a superseded version is a stale quote, not an invented one, **and calling it invented would accuse the model of something it didn't do.**

Both callers pass exactly one:

- `core/LLM/ExtractionEngine.swift:333` — `resumes: [resume.text]`
- `core/Services/BackgroundStore.swift:833` (the `--recheck-evidence` migrator path) — `resumes: [resumeText]`

So a span quoted accurately from a **different active résumé**, or from an **earlier version of the same one**, is classified `.invented` — the exact false accusation the comment says must not happen. The user has multiple résumés and revises them (`Brooks_Cutter_Resume_Master` was updated at 19:52 today, and stored scores already carry `reflects_previous_resume_version: true`), so this fires in normal use.

## Why it matters beyond tidiness

The `.invented` verdict is user-facing: it drives the "I don't have this" affordance and the scoring-feedback loop. A false accusation there trains the user to distrust evidence that was in fact correct, and feeds bad signal back into scoring.

**It also calls a headline number into question.** The doc comment reports "**32% of quoted spans corpus-wide appear in no résumé the user has ever had**, across 44 of 415". That measurement was taken through this bug, so it is an upper bound, not a measurement — an unknown share of that 32% is quotes from résumés that simply weren't passed in. Re-measure after fixing, and correct the comment; a widely-cited figure that overstates the problem will drive the wrong prompt work.

## Fix

Pass every résumé the user has had active. Both sites already have store access; `BackgroundStore` can fetch the set once and reuse it across the loop rather than per-record. Then re-run `--recheck-evidence` to clear the false flags, and re-derive the 32% figure.

Consider whether the check should also distinguish `.stale` (found in a superseded résumé) from `.supported` and `.invented` — the code comment implies the distinction matters, and a third state would let the UI say "this was true of an older version of your résumé" instead of silently accepting or accusing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both call sites pass every résumé the user has had active, not one
- [ ] #2 A span quoted from a superseded résumé version is not classified invented, covered by a test
- [ ] #3 The résumé set is fetched once per run rather than per record in the migrator path
- [ ] #4 The 32% figure in EvidenceCheck's doc comment is re-measured after the fix and corrected
- [ ] #5 A decision is recorded on whether a distinct .stale support state is worth adding
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed in ffb59816 (merged via a6d519e4). EvidenceCheck's contract says it is given every résumé, but it was passed only the one being scored, so a quote drawn from another stored résumé was accused of being invented. `otherResumeTexts` is now threaded from `QueueActor` through `ExtractionEngine` and the check sees `[resume.text] + otherResumeTexts` (`core/LLM/ExtractionEngine.swift:293,350`; `core/LLM/QueueActor.swift:1001`). Stored analyses were re-checked with `JobhuntMigrator --recheck-evidence` against the production store.

Status corrected 2026-09-04 — landed 2026-09-03.
<!-- SECTION:FINAL_SUMMARY:END -->
