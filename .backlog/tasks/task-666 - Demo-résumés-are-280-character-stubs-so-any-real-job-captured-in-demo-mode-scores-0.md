---
id: TASK-666
title: >-
  Demo résumés are 280-character stubs, so any real job captured in demo mode
  scores 0
status: To Do
assignee: []
created_date: '2026-08-05 19:16'
labels:
  - demo
  - fit-scoring
  - onboarding
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Measured live: two real postings captured into demo mode via the browser extension, scored with the real model (`deepseek/deepseek-v4-flash` on OpenRouter), both came back **0**.

| Posting | Match quality | Score |
|---|---|---|
| Duolingo — Senior PM, Monetization (New York) | Weak (consumer monetization vs TPM résumé) | **0** |
| Reddit — **Staff Technical Program Manager** (Remote US) | **Strong** — TPM, staff level, remote, infra-adjacent | **0** |

The second one is the tell. That posting is close to a bullseye for the demo résumé, and it still scored zero.

**Cause: the demo résumés are stubs.** `DemoSeeder` seeds "TPM Resume — Full" at `charCount: 280` and "TPM Resume — Condensed" at `175` — three sentences of summary prose, no employment history, no projects, no metrics, no tools. Against a real posting listing 15–20 requirements, nearly every requirement is unevidenced, the penalty saturates the 60-point cap, and the score floors at 0.

This is invisible for the *seeded* jobs, because their analyses are generated rather than scored — so the demo looks fine until someone captures something real.

**Why it matters.** Demo mode exists so a prospective user can evaluate the app. The obvious first thing to try is capturing a job you actually care about — and it comes back 0 with a wall of red X's, which reads as "this product doesn't work". It also blocks recording any honest marketing footage of the capture → extract → score flow, which is the product's core loop.

**Fix:** give the demo a realistic full résumé — a fabricated but complete TPM history (roles, dates, scope, metrics, technologies), on the order of 3–5k characters, the length of a real two-page résumé. Keep it obviously fictional (invented employers), and keep both résumés so the multi-résumé comparison still demonstrates.

**Note the interaction with [TASK-656].** A thin résumé makes penalty saturation dramatic, but the underlying arithmetic is what turns "poorly evidenced" into exactly 0 rather than, say, 25. Fixing the résumé makes the demo usable; fixing the penalty model is what makes the score meaningful. Both are needed, and 656 should be validated against a real capture, not only the stored corpus.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Demo résumés are realistic full-length documents, not summary stubs
- [ ] #2 A real job posting captured into demo mode scores plausibly rather than 0
- [ ] #3 Both a strong-match and a weak-match posting are checked, and the scores are ordered correctly relative to each other
- [ ] #4 The résumés remain obviously fictional (invented employers)
- [ ] #5 Two résumés are retained so the multi-résumé comparison still demonstrates
<!-- AC:END -->
