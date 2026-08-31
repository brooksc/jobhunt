---
id: TASK-712
title: >-
  Stored résumés must carry no meta-commentary — the scorer reads "do not claim
  X" as the candidate lacking X
status: To Do
assignee: []
created_date: '2026-08-31 21:05'
labels: []
dependencies: []
priority: medium
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
