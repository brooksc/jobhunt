---
id: TASK-707
title: >-
  Newly-scored jobs ignore your scoring feedback — the queue never passes it to
  scoreFit
status: To Do
assignee: []
created_date: '2026-08-31 20:37'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while documenting fit scoring (2026-08-31, `docs/fit-scoring.md`). **Verified.**

`ExtractionEngine.scoreFit` (`core/LLM/ExtractionEngine.swift:274-281`) accepts scoring feedback:

```swift
public static func scoreFit(
    job: JobFitSnapshot,
    resume: ResumeSnapshot,
    model: String,
    provider: any LLMProvider,
    feedback: [ScoringFeedback] = [],   // ← defaulted
    jobNumber: Int? = nil
) async throws -> FitScoreOutput
```

`QueueActor.swift:978` — the path every automatically-queued fit score goes through — **omits the argument**, so it silently defaults to `[]`.

The feedback *is* threaded correctly through the recompute-from-stored-JSON path (`BackgroundStore.swift:974` → `FitScorer.rescoreFromJSON(_:feedback:jobNumber:)`), and `ScoringVariant`/`FitScorer` handle it throughout. So the machinery works — it just isn't wired to the one place that produces new scores.

**Effect:** every "I don't have this" correction the user records is ignored by every job scored afterwards. The correction only takes effect if something later recomputes that job from its stored JSON. A user teaching the scorer sees no change on incoming jobs and reasonably concludes the feature does nothing.

**Why it went unnoticed: the parameter has a default.** Omitting it is not a compile error and produces no warning — the same shape as [[TASK-695]] (`insertSavedSearch` safe only by accident) and TASK-702 (a settings key missing from a hand-maintained list). A default value on a parameter that should always be supplied is a silent-failure generator.

## Fix

Fetch the user's `ScoringFeedback` in `QueueActor` before scoring and pass it. Note the actor's closure-based-init convention (`CLAUDE.md`): read it through an injected closure rather than reaching into the store directly, matching `readExtractionSettings`.

Then consider **removing the default** from `scoreFit`'s `feedback:` parameter so a future caller must decide explicitly. That converts this class of bug from silent to compile-time, which is the same reasoning behind marking `insertSavedSearch`'s parameter `sending`.

Also worth checking: does a newly scored job need re-scoring once feedback exists, or is applying it going forward sufficient? Recording the answer avoids someone re-litigating it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 QueueActor passes the user's ScoringFeedback to scoreFit for every newly queued fit score
- [ ] #2 Feedback is read through an injected closure, consistent with the QueueActor closure-init convention
- [ ] #3 A test asserts a newly scored job reflects an existing 'I don't have this' correction
- [ ] #4 The default on scoreFit's feedback: parameter is removed, or a reason for keeping it is recorded
- [ ] #5 A decision is recorded on whether previously scored jobs should be re-scored when feedback is added
<!-- AC:END -->
