---
id: TASK-623
title: 'Dashboard: Daily accomplishments and end-of-day recap'
status: Done
assignee: []
created_date: '2026-07-22 20:59'
updated_date: '2026-08-10 01:31'
labels:
  - dashboard
  - wellbeing
  - workflow
  - analytics
dependencies: []
references:
  - app/JobHunt/Features/Dashboard/DashboardView.swift
  - core/Services/DashboardMetrics.swift
  - core/Models/JobEvent.swift
  - core/Models/JobAction.swift
modified_files:
  - core/Services/DashboardMetrics.swift
  - core/Services/BackgroundStore.swift
  - core/Models/Setting.swift
  - core/Settings/SettingsStore.swift
  - app/Views/Dashboard/CloseOutDaySheet.swift
  - app/Views/Dashboard/TodayRecapCard.swift
  - app/Views/Settings/SettingsTab.swift
  - app/Platform/PlatformIntegration.swift
  - app/Shell/AppServices.swift
  - tests/CoreTests/DailyRecapNarrativeTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Turn the Dashboard into a humane record of daily progress for an active job seeker. The primary value is emotional closure: at the end of a day, the user should be able to see the meaningful work they completed and leave with a concrete sense of momentum. Summarize jobs found or captured, jobs reviewed/triaged, roles moved to Interested, applications submitted, follow-ups completed, and meaningful interview or offer milestones. Reward progress without streak pressure, quotas, guilt, or social comparison. Keep user actions distinct from background extraction and AI processing. The recap should use authoritative timestamped domain activity so historical days remain correct even after a job's current status changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Dashboard prominently summarizes today's jobs found or captured, jobs reviewed or triaged, jobs marked Interested, jobs marked Applied, and follow-ups completed.
- [x] #2 The summary includes meaningful interview and offer milestones when they occur without allowing rare outcomes to overshadow effort.
- [x] #3 A concise natural-language recap describes the day's accomplishments and can be opened as an explicit Close Out My Day view.
- [x] #4 The user can review prior days over at least 7-day and 30-day ranges and select a day to see the jobs and actions behind its totals.
- [x] #5 Counts derive from authoritative timestamped activity rather than current-status snapshots, so later status changes do not rewrite prior-day history.
- [x] #6 Repeated or idempotent operations do not inflate activity totals, and status transitions are interpreted through a centralized structured representation rather than UI-specific parsing of display notes.
- [x] #7 User-initiated progress is visually distinct from background captures, extraction, scoring, and other automated processing.
- [x] #8 Local calendar day boundaries and timezone changes are handled consistently and covered by focused tests.
- [x] #9 Zero-activity days use a neutral, supportive presentation; the feature has no streak-loss treatment, red failure state, quota, ranking, or social comparison.
- [x] #10 Each metric can reveal the relevant jobs or actions so the recap is auditable rather than a disconnected counter.
- [x] #11 Any end-of-day reminder is optional, disabled by default, and configurable without penalizing a user for dismissing it.
- [ ] #12 not verified: (visual) — keyboard traversal, VoiceOver output and Dynamic Type were not exercised on a live desktop. Every control is a standard SwiftUI Button/Picker (so focusable by default), rows carry explicit accessibility labels, and no text uses a fixed frame height.
<!-- AC:END -->



## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Backlog drift correction (2026-07-25): this sat In Progress with 0/12 checked while most of it had shipped. Verified against the code and checked off #1/#2/#5/#6/#7/#10 — TodayRecapCard renders the counters, DashboardMetrics.category is the single shared categorizer for counts and drill-in, counts derive from immutable JobEvents (not status snapshots), background extraction/AI events are excluded, and every metric drills into the jobs behind it.

Genuinely outstanding: #3 (natural-language recap / explicit "Close Out My Day" view — no closeOut symbol exists anywhere) and #11 (optional, default-off end-of-day reminder — no endOfDay setting exists). #4 is partial: buildRecapWindow powers a multi-day strip and days drill in, but the 7/30-day range selection isn't there. #8/#9/#12 not separately re-verified.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Picked up with #1, #2, #5, #6, #7, #10 already done. This closes the rest.

**#3** `DailyRecap.recapSentence` writes the day as prose — "Today you sent 3 applications and shortlisted 2 roles" — because closure comes from reading what you did, not from a row of numbers. Ordered by what someone is likeliest to feel good about rather than by magnitude, so one offer leads over twelve saved jobs, and capped at three clauses: a sentence with ten stops being a sentence. `CloseOutDaySheet` is the explicit view, opened from the card.

**#4** The sheet carries a 7/30-day picker and lists each active day; selecting one opens the existing drill-in. It lists **only days with activity** — a column of empty rows turns "your history" into "everything you didn't do", which is the tone this feature exists to avoid.

**#8** `RecapReminderSchedule.nextFireDate` is pure, so day boundaries are testable without waiting a day. Two behaviours worth naming: it holds the **wall-clock hour across a DST transition** rather than drifting an hour twice a year, and firing *exactly* on the hour rolls to tomorrow rather than re-firing on every tick.

**#9** Empty days read "No tracked activity today", and the sheet adds that plenty of days look like that. Tests assert the recap contains none of *streak, missed, failed, behind, should, goal, quota, keep it up* in either the empty or the busy state — that constraint is easy to reintroduce by accident in a later copy edit, so it's pinned rather than trusted.

**#11** Off by default, hour configurable, and the loop re-reads the setting each cycle so turning it off takes effect without a relaunch. The notification carries the day's own sentence rather than nagging the user to come and look.

**#12** rewritten `not verified: (visual)`. Every control is a standard SwiftUI `Button`/`Picker`, so keyboard-focusable by default; day rows are single accessibility elements with labels that say what activating them does; no text is height-constrained. Exercising VoiceOver and Dynamic Type needs a live desktop.

15 tests. Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 359 files, swiftformat 0.61.1 clean, warning ratchet 58/58, tooltip check passes.
<!-- SECTION:FINAL_SUMMARY:END -->
