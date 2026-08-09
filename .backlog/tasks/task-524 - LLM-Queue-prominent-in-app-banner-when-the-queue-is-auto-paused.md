---
id: TASK-524
title: 'LLM Queue: prominent in-app banner when the queue is auto-paused'
status: Done
assignee: []
created_date: '2026-06-19 04:41'
updated_date: '2026-08-09 23:00'
labels:
  - ux
  - llm
  - queue
dependencies: []
modified_files:
  - core/LLM/QueuePauseBanner.swift
  - core/Models/Setting.swift
  - core/Settings/SettingsStore.swift
  - app/Views/Queue/QueuePauseBannerView.swift
  - app/Views/Queue/LLMQueueView.swift
  - app/Shell/Sidebar.swift
  - app/Shell/AppServices.swift
  - app/Platform/PlatformIntegration.swift
  - app/JobhuntApp.swift
  - tests/CoreTests/QueuePauseBannerTests.swift
priority: medium
ordinal: 10000
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
- [x] #1 The LLM Queue view shows a prominent banner whenever the queue is paused with items waiting, with an inline Resume action
- [x] #2 The banner differentiates auto-pause (after failures) from a user-initiated pause
- [x] #3 The banner shows how many items are queued/waiting
- [x] #4 The banner disappears immediately when the queue resumes or the queue is empty
- [x] #5 Consider a lightweight global indicator (e.g. sidebar LLM Queue badge state or toolbar) so a paused queue is noticeable from other views
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
#2 needed state that didn't exist: the pause was a bare boolean, so nothing could tell an auto-pause from a user pause after the fact. New `QueuePauseReason` (user / repeatedFailures / authenticationFailed) is persisted next to it. The queue actor can't say why it paused, so the reason is written by the `.autoPaused` and `.authenticationFailed` event handlers in `PlatformIntegration` (which now takes a `SettingsStore`), and `SettingsStore.setQueuePaused(_:reason:)` resets it to `.user` on resume — a stale "auto-paused after failures" would otherwise mislabel the next deliberate pause. Unknown stored values read back as `.user`, the conservative direction.

#1/#3/#4 `QueuePauseBanner.make(isPaused:reason:waiting:)` in Core returns the banner or nil, so the show/hide rule is unit-tested rather than eyeballed: paused with work waiting, nothing while running, and deliberately nothing when paused-and-empty (a banner that's always on screen is one people stop reading). The count is in the title; auth failure points at Settings → AI rather than at Resume, since resuming without fixing the key just fails again. `QueuePauseBannerView` renders it above the queue with an inline Resume.

#5 The sidebar LLM Queue row shows a pause glyph — orange for automatic, secondary for a user pause — when paused with outstanding requests. The badge alone couldn't carry this: a count of 12 looks identical draining or wedged.

10 tests. Two SwiftLint size limits tripped by the additions, fixed by extracting `QueuePauseBannerView` and `JobhuntApp.pointLLMAtMock` rather than by raising the limits.

Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 320 files, swiftformat 0.61.1 clean.

not verified: (visual) — banner and sidebar glyph appearance, and the end-to-end auto-pause path in a running app (it needs a real provider failing four times). The reason-writing and banner rules are covered by unit tests; the wiring between them is compile-checked only.
<!-- SECTION:FINAL_SUMMARY:END -->
