---
id: TASK-524
title: 'LLM Queue: prominent in-app banner when the queue is auto-paused'
status: To Do
assignee: []
created_date: '2026-06-19 04:41'
labels:
  - ux
  - llm
  - queue
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When the LLM queue auto-pauses after a failure streak (QueueActor emits .autoPaused, PlatformIntegration posts a critical "AI Queue Paused" notification), queued work silently piles up and nothing runs. The only on-screen cue is the small green "Resume" button in the queue header — easy to miss. Users hit this and think new captures / re-queued fit scoring are "broken" when the queue is simply paused (observed: a user queued 4 fit scores + reset a failed extract, none ran, because an earlier flaky extraction had auto-paused the queue).

Add a clear, in-app banner at the top of the LLM Queue view (and ideally a global cue) when the queue is paused — especially when auto-paused — e.g. "AI queue auto-paused after repeated failures — N items waiting. [Resume]". The banner should:
- Distinguish auto-pause (after failures) from a deliberate user pause.
- Show the count of queued/waiting items so the cost of staying paused is visible.
- Offer a one-click Resume inline.
- Clear itself the moment the queue resumes.

Context: the auto-pause is now far less trigger-happy after raising autoPauseThreshold 2→4 and no longer counting in-flight cancellations as failures (commit 8c5740d), but it can still happen, and when it does the user needs an obvious, in-context nudge rather than only a transient macOS notification.

References: app/Views/Queue/LLMQueueView.swift, app/Platform/PlatformIntegration.swift (.autoPaused handler), core/LLM/QueueActor.swift (autoPauseThreshold, onSetPaused), core/Settings/SettingsStore.swift (llmQueuePaused).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The LLM Queue view shows a prominent banner whenever the queue is paused with items waiting, with an inline Resume action
- [ ] #2 The banner differentiates auto-pause (after failures) from a user-initiated pause
- [ ] #3 The banner shows how many items are queued/waiting
- [ ] #4 The banner disappears immediately when the queue resumes or the queue is empty
- [ ] #5 Consider a lightweight global indicator (e.g. sidebar LLM Queue badge state or toolbar) so a paused queue is noticeable from other views
<!-- AC:END -->
