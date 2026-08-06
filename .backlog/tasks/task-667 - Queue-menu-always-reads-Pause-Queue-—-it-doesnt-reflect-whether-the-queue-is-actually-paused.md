---
id: TASK-667
title: >-
  Queue menu always reads "Pause Queue" — it doesn't reflect whether the queue
  is actually paused
status: To Do
assignee: []
created_date: '2026-08-06 02:54'
labels:
  - llm-queue
  - ui
dependencies:
  - TASK-524
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The **Queue** menu bar item contains a single command that always reads **"Pause Queue"**, regardless of state. Meanwhile the LLM Queue view shows a green **Resume** control and `Running 0`.

Reproduced three times in one session on a freshly seeded store:

```
Queue menu:  [Pause Queue]                    <- implies it is running
Queue view:  Queued 1  Running 0  Failed 0   > Resume    <- it is paused
```

Clicking Resume in the view starts processing; the menu item still reads "Pause Queue" afterwards, so it is not a toggle that got stuck — it appears to be a static label with no binding to the paused state.

**Why it matters more than it looks.** The queue starts paused on a fresh store. A user captures their first job, nothing happens, and the one obvious place to check — the Queue menu — actively tells them the queue is running. The only correct signal is a small green link inside a view most users won't have opened. During this session it cost three separate diagnostic detours, with full knowledge of the codebase.

This is the same wound as [TASK-524] (no prominent banner when the queue is auto-paused) seen from the other side: 524 adds a signal where there is none; this fixes a signal that is actively wrong. A wrong indicator is worse than a missing one.

**Fix:** bind the menu item's title (and ideally its state) to the queue's `isPaused`, so it reads "Resume Queue" when paused. Worth auditing whether any other menu command is a static label where it should reflect state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Queue menu reads 'Resume Queue' when the queue is paused and 'Pause Queue' when it is running
- [ ] #2 The label updates without reopening the menu or restarting the app
- [ ] #3 Toggling from the menu and from the queue view leave the two in agreement
- [ ] #4 Other menu commands are spot-checked for static labels that should reflect state
<!-- AC:END -->
