---
id: TASK-667
title: >-
  LLM Queue toolbar button always reads "Resume Queue", even while the queue is
  running
status: Done
assignee: []
created_date: '2026-08-06 02:54'
updated_date: '2026-08-09 18:47'
labels:
  - llm-queue
  - ui
dependencies:
  - TASK-524
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Correction — my original report blamed the wrong control.** I filed this as "the Queue *menu* is a static label". It isn't: `AppCommands.swift:29` binds it correctly —

```swift
Button(handlers?.isPaused == true ? "Resume Queue" : "Pause Queue") { handlers?.togglePause() }
```

The menu was reading "Pause Queue" because the queue genuinely **was not paused**. The menu was right and I misread it.

The actually-misleading control is the **toolbar button in the LLM Queue view** (`LLMQueueView.swift:297`). It is a plain action button, permanently labelled **"Resume Queue"** with a play icon, that calls `processAll()`:

```swift
Button { Task { await processAll() } } label: { Label("Resume Queue", systemImage: "play.fill") }
```

It renders identically whether the queue is running, paused, or idle. So a user (or an agent debugging it) sees "▶ Resume Queue", concludes the queue is paused, and starts chasing a pause that never existed. That happened three times in one session here, and it sent me looking for a phantom bug instead of the real one — [TASK-657]'s wedge, where the queue is unpaused but a stale drain makes every start a no-op.

**Fix:** label it for what it does, not for a state it doesn't reflect — "Run Queued Requests" or similar — or bind it to `isPaused` the way the menu already is. If it stays an unconditional action, it must not use pause/resume vocabulary.

Note the semantics differ from the menu's: the menu *toggles pause*, this button *starts a drain*. Two different operations sharing one name is most of the confusion.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The queue toolbar control does not imply a paused state when the queue is running
- [x] #2 Its label describes the action it performs, distinct from the menu's pause/resume toggle
- [ ] #3 not verified (visual): a user can tell at a glance whether the queue is paused, running, or idle — the status pill is implemented and its state derivation is unit-tested, but the rendered appearance was not checked, since driving the UI is out of scope for this run
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Two changes.

**The toolbar button is named for what it does.** `Label("Resume Queue", systemImage: "play.fill")` → `Label("Run Queued Requests", systemImage: "play.circle")`, and it is now disabled when nothing is queued. It starts a drain; the pause *toggle* lives in the summary bar and the Queue menu. Two different operations sharing one name was most of the confusion.

**The queue's actual state is now displayed.** New `QueueActivity` in JobhuntCore derives Paused / Running / Waiting / Idle from `(isPaused, running, queued)`, rendered as a coloured pill in `QueueSummaryBar` with a tooltip and a combined accessibility label.

`queued` is deliberately its own state rather than folded into `running`. Outstanding work with nothing executing and no pause in force is exactly the TASK-657 wedge, and calling it "Running" would hide the one symptom that gives it away.

The derivation lives in Core rather than the view so it can be tested — `JobsView`-style app code has no unit-test target. Five tests: paused wins over in-flight work, running when executing, waiting distinct from running, idle when empty, and every state carries both a label and an explanation.

Criterion 3 is marked **not verified**: the pill renders from tested logic, but I did not look at it. Driving the UI was out of scope for this run.
<!-- SECTION:FINAL_SUMMARY:END -->
