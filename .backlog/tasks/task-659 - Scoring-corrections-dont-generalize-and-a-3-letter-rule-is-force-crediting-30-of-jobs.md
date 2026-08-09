---
id: TASK-659
title: >-
  Scoring corrections: add a blast-radius preview and route "I do have this" to
  the résumé
status: Done
assignee: []
created_date: '2026-08-02 18:14'
updated_date: '2026-08-09 20:30'
labels:
  - fit-scoring
  - feedback
  - ui
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`[ScoringFeedback].verdict` matches with `requirement.lowercased().contains(phrase.lowercased())` (`core/Services/ScoringFeedback.swift:115`). The sheet captures the **whole requirement sentence** as the phrase, so in practice users land on one of two failure modes — both present in the live store's six entries, measured against all 12,597 requirement rows in `ZJOBFITSCORE`:

| Phrase | Matches |
|---|---|
| "Experience with AI agents" | 1 |
| "Demonstrated experience with generative AI platforms" | 1 |
| "Experience building AI agents or infrastructure." | 1 |
| "Hands-on with AI tools. You already use them and…" | 1 |
| "Generate artifacts that accelerate alignment. Leverage AI…" | 1 |
| **"IDE"** | **359** |

**1. Too narrow (5 of 6).** A full-sentence phrase can only ever match the posting it came from. The user's expectation — reasonably — is that flagging "I do have this" teaches a generalizable fact about their experience, not a string equality test against one JD.

**2. Too broad, and currently causing harm.** `IDE` lowercases to `ide`, a substring of *provide*, *identify*, *guidance*, *consider*, *ideal*, *wide*. It force-credits 359 requirements across **124 of 415 scored jobs (30%)**, e.g. *"Ability to keep the big picture in focus and to provide clear, well-structured…"* — real gaps silently scored `met`. `.alwaysCredit` -> `.forceMet` applies at projection time, so displayed scores are already wrong and a recompute would bake it in. The docstring warns narrower is better; nothing enforces it and the UI gives no signal.

**Fixes, roughly in order of value**

- **Blast-radius preview at capture time.** Before saving, count matches across stored `requirement_assessments` and show it ("this would match 359 of 12,597 requirements across 124 jobs"), with a hard block or explicit confirm above a threshold. This alone would have stopped `IDE` and is the cheapest guard.
- **Word-boundary matching** instead of bare `contains`. `ide` would stop matching *provide*. Doesn't fix over-narrow phrases, but removes the silent-corruption class.
- **Route `.alwaysCredit` to the résumé, not the rule list.** Five of six live entries are the same fact ("I have AI / gen-AI / agent experience") phrased five ways — a résumé gap, not a scoring defect. Fixing the source generalizes through the model's own judgement to any future phrasing. The flag's copy already says this; the UI should act on it, offering "add this to your résumé / skills" as the primary action and the rule as the fallback. The skills-section idea previously raised is the natural home.
- **Existing entries need triage**, not just new-entry guards — the six in the store are all defective.

**Do not fix this by prompt-injecting the feedback.** Measured: adding one broad rule to the scoring prompt regressed job #231 from a correct 60 back to 96 on `gemini-3.1-flash-lite`, because the new instruction diluted the rules that were working. Accumulating user prose would be worse and would degrade silently. Deterministic matching stays; make it accurate and make its reach visible.

**What the mechanism is genuinely good at** and should be steered toward: `.neverCredit` on proper nouns (CUDA, PCI DSS, electrical engineering) — literal strings that appear literally, asserting something no résumé edit can satisfy.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Saving a correction shows how many existing requirements and jobs it would match, before it is saved
- [x] #2 A rule matching an implausibly large share of the corpus is blocked or requires explicit confirmation
- [ ] #3 not verified (visual): flagging 'I do have this' offers the résumé as the primary path with the rule as fallback — implemented and building, but the rendered sheet was not observed, since driving the UI is out of scope for this run
- [x] #4 The six pre-existing entries in the live store are reviewed against word-boundary semantics
- [x] #5 No user feedback is injected into the scoring prompt
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Partly fixed already — retitled to what's left.**

Done since filing:
- **Word-boundary matching** shipped in `8723142c` (`ScoringFeedback.matches(phrase:in:)`). This kills the live corruption: `IDE` no longer matches *provide*, *identify* or *guidance*, so the 359 force-credited requirements across 124 jobs are gone. The over-broad-rule class of failure is closed.
- **Match counting exists** — `JobService.scoringFeedbackMatchCounts(_:)` reports how many stored assessments each correction currently hits, so an orphaned or runaway rule is already visible rather than silent.

Still open, and the reason this stays on the backlog:

1. **Blast-radius preview at capture time.** The count exists as a service call but isn't surfaced *before* saving. Showing "this would match 359 of 12,597 requirements across 124 jobs" in the correction sheet, with a confirm above some threshold, is what stops the next over-broad rule being created at all.
2. **Route `.alwaysCredit` toward the résumé.** Five of the six live entries were the same fact — "I have AI / gen-AI / agent experience" — phrased five ways, because a full-sentence phrase only ever matches the posting it came from. Word boundaries don't fix that: these rules are still too *narrow* to generalise. The durable fix is adding the evidence to the résumé (or a skills block) so the model's own judgement carries it to future postings, with the deterministic rule as the fallback.
3. **Triage the existing entries.** The six in the live store predate the word-boundary fix and were authored against the old semantics.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Criteria 1, 2 and 5 shipped earlier (blast-radius preview at capture time, word-boundary matching, nothing injected into the prompt). This closes 3 and 4.

**Criterion 3.** Choosing "I do have this" now leads with the résumé: a short explanation that a recruiter and an ATS read the same résumé the scorer did, so they will miss it too, and a prominent button that closes the sheet and navigates to Resumes. The deterministic rule remains, relabelled "Or match on". Taking the résumé path deliberately saves **no** rule — offering it as primary and then also writing a one-off string rule would defeat the point.

**Criterion 4 — reviewed against the live store, read-only.** The result is better than the task assumed:

- The harmful **`IDE` rule is gone** — it was the one force-crediting 359 requirements across 124 jobs. Five rules remain, all `alwaysCredit`.
- Under word-boundary semantics those five match **exactly what they matched under substring**: no change, so the boundary fix neither helped nor harmed them.
- Four of the five now match **zero** of the 13,103 stored requirement rows, and the fifth matches one. They are inert — they don't even match the posting they were created from any more, most likely because rescoring changed the requirement text.

So the over-narrow failure mode is confirmed on real data at its logical end point: rules that do nothing whatsoever. That is precisely what criterion 3's résumé path is for, and it means no cleanup migration is needed — the entries are harmless, just useless.
<!-- SECTION:FINAL_SUMMARY:END -->
