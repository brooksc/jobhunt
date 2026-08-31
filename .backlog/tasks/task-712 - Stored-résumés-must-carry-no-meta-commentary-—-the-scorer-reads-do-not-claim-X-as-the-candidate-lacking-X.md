---
id: TASK-712
title: >-
  Stored résumés must carry no meta-commentary — the scorer reads "do not claim
  X" as the candidate lacking X
status: To Do
assignee: []
created_date: '2026-08-31 21:05'
updated_date: '2026-08-31 21:38'
labels: []
dependencies: []
priority: low
type: docs
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From `docs/ai-prompts-review-2026-08-31.md` §6. New evidence rather than a code reading, and invisible from inside the app.

The stored résumé is prose the scorer reads as **evidence about the candidate**. If that text contains editorial instructions *about* the résumé — "do not claim X", "this was coordination, not ownership", correction notices — the scorer reads them as facts about the person. Calibration notes intended for a writing agent become, to the scorer, a list of things the candidate cannot do, sitting directly beside the skills they annotate.

Observed concretely: `Brooks_Cutter_Resume_Master` had accumulated framing caveats and do-not-claim lists, totalling ~51,755 characters of which roughly **6,800 were agent-facing annotation**. It now stands at 45,104 characters (edited 2026-08-31 21:01).

**The failure has no symptom.** Scores come back plausible, just uniformly lower, and nothing indicates why — so it can persist indefinitely.

## What to do

- Note in the résumé-import path and/or user-facing help that the stored résumé should be **the document a recruiter would read**, with no editorial or meta-commentary.
- Consider a soft warning at import when the text contains obvious annotation markers (imperative "do not…", "note to self", bracketed editorial asides). A heuristic here is low-risk because the remedy is advisory, not automatic — but do not silently strip anything; the user must stay in control of their own résumé text.

## Why it matters beyond this one document

It strengthens the case for a shorter, purpose-built résumé from a second direction. `docs/ai-prompts.md` §10.1 argues for that on **cost** grounds — the 45 KB master is ~85% of a 42,000-character fit prompt at $0.0117 per score. This is the **accuracy** argument: a 6 KB targeted variant is unlikely to contain meta-commentary, while a 45 KB master maintained by hand over months is likely to. The four inactive targeted résumés in the store (~5.6–6.0 KB each) are the existing precedent.

Quantifying the effect is part of [[TASK-710]] — re-score a sample against the pre- and post-edit résumé text. If it moves scores materially, every stored score predating today's edit is affected, which bears directly on [[TASK-711]].
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The résumé import path or help text states that stored résumés must contain no editorial or meta-commentary
- [ ] #2 A decision is recorded on whether to warn at import when annotation markers are detected
- [ ] #3 Nothing is silently stripped from the user's résumé text
- [ ] #4 The measured effect from TASK-710 is recorded here once known
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: primary
created: 2026-08-31 21:38
---
**Measured 2026-08-31 ([[TASK-710]]). Null result, and the premise was wrong on both halves.**

1. **The effect is null.** Scoring a sample against annotated vs cleaned résumé text gave Δ = **+0.50 ± 2.78** — comfortably inside the σ = 3.16 noise floor. The meta-commentary is not measurably depressing scores.
2. **No 51,755-character version exists.** The review reported the master résumé had been cleaned from ~51,755 to 45,104 characters. The benchmark could not find any such earlier text, and **the meta-commentary is still present in the live résumé** at 45,104 characters. So the cleanup the review describes as done has not happened, and the size change it attributes to that cleanup is something else.

A caveat the benchmark states honestly: its `resume_old` comparison confounds meta-commentary with four weeks of ordinary content drift, so it is not a clean isolation of the annotation effect. But the direction and magnitude give no reason to act.

**Downgraded to Low.** The advice is still sound in principle — a scorer reading "do not claim X" as a fact about the candidate is a real failure mode, and documenting that stored résumés should read as a recruiter would read them costs nothing. It is simply not worth engineering effort: no import-time warning, no detection heuristic. A sentence in the help text is the whole appropriate response.

The cost argument for a shorter résumé survives and is stronger than the accuracy one — the 45k master is ~11.1k of ~14k prompt tokens per call. That moves to [[TASK-713]], which is about variance and cost rather than accuracy.
---
<!-- COMMENTS:END -->
