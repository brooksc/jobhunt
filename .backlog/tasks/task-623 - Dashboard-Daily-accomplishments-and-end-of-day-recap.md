---
id: TASK-623
title: 'Dashboard: Daily accomplishments and end-of-day recap'
status: In Progress
assignee: []
created_date: '2026-07-22 20:59'
updated_date: '2026-07-25 21:35'
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
- [ ] #3 A concise natural-language recap describes the day's accomplishments and can be opened as an explicit Close Out My Day view.
- [ ] #4 The user can review prior days over at least 7-day and 30-day ranges and select a day to see the jobs and actions behind its totals.
- [x] #5 Counts derive from authoritative timestamped activity rather than current-status snapshots, so later status changes do not rewrite prior-day history.
- [x] #6 Repeated or idempotent operations do not inflate activity totals, and status transitions are interpreted through a centralized structured representation rather than UI-specific parsing of display notes.
- [x] #7 User-initiated progress is visually distinct from background captures, extraction, scoring, and other automated processing.
- [ ] #8 Local calendar day boundaries and timezone changes are handled consistently and covered by focused tests.
- [ ] #9 Zero-activity days use a neutral, supportive presentation; the feature has no streak-loss treatment, red failure state, quota, ranking, or social comparison.
- [x] #10 Each metric can reveal the relevant jobs or actions so the recap is auditable rather than a disconnected counter.
- [ ] #11 Any end-of-day reminder is optional, disabled by default, and configurable without penalizing a user for dismissing it.
- [ ] #12 The recap is keyboard accessible, supports VoiceOver labels, and remains legible at supported text sizes.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Backlog drift correction (2026-07-25): this sat In Progress with 0/12 checked while most of it had shipped. Verified against the code and checked off #1/#2/#5/#6/#7/#10 — TodayRecapCard renders the counters, DashboardMetrics.category is the single shared categorizer for counts and drill-in, counts derive from immutable JobEvents (not status snapshots), background extraction/AI events are excluded, and every metric drills into the jobs behind it.

Genuinely outstanding: #3 (natural-language recap / explicit "Close Out My Day" view — no closeOut symbol exists anywhere) and #11 (optional, default-off end-of-day reminder — no endOfDay setting exists). #4 is partial: buildRecapWindow powers a multi-day strip and days drill in, but the 7/30-day range selection isn't there. #8/#9/#12 not separately re-verified.
<!-- SECTION:NOTES:END -->
