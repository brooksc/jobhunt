---
id: TASK-659
title: >-
  Scoring corrections don't generalize, and a 3-letter rule is force-crediting
  30% of jobs
status: To Do
assignee: []
created_date: '2026-08-02 18:14'
labels:
  - fit-scoring
  - feedback
  - ui
dependencies: []
priority: high
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
- [ ] #1 Saving a correction shows how many existing requirements and jobs it would match, before it is saved
- [ ] #2 A rule matching an implausibly large share of the corpus is blocked or requires explicit confirmation
- [ ] #3 Matching respects word boundaries: a phrase 'IDE' no longer matches 'provide' or 'identify'
- [ ] #4 The existing six entries in the live store are triaged; the 'IDE' rule is gone
- [ ] #5 Flagging 'I do have this' offers adding the experience to the resume/skills as the primary path, with the deterministic rule as fallback
- [ ] #6 No user feedback is injected into the scoring prompt
- [ ] #7 A test asserts a short phrase cannot silently force-credit unrelated requirements
<!-- AC:END -->
