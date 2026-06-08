---
id: TASK-060
title: 'Platform integration: notifications, dock badge, deep links, Sparkle (DMG)'
status: To Do
assignee: []
created_date: '2026-06-07 22:51'
labels:
  - swift-rewrite
  - ui
  - platform
milestone: m-1
dependencies:
  - TASK-045
  - TASK-044
  - TASK-047
  - TASK-041
documentation:
  - swift-plan.md
  - electron/main.js
priority: medium
ordinal: 3700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the native macOS integration currently in electron/main.js — notifications, dock badge, jobhunt:// deep links, window focus bridge, and Sparkle auto-update (DMG flavor only).

## Read first
- swift-plan.md §10.5 (platform integration details + notification rules), §13.4 (Sparkle, DMG only, from v1), §8.6 (engine events), §7 (focus bridge from the server).
- Legacy electron/main.js — the authority: dock badge = unread count; showMacNotification logic incl. high-fit emphasis and the "don't flood on big batches" rule; job-ready / job-unavailable / ai-processing-complete / queue-auto-paused handling (critical → dock bounce + navigate to LLM Queue); jobhunt://jobs/N deep links; /api/app/focus bridge; activate/reopen behavior.

## Implement (app/Platform/)
- Subscribe to the engine's domain-event stream (task-044) + availability events (task-041); map to UNUserNotificationCenter notifications with the same gating rules; click → focus + navigate via Router (task-045).
- Dock badge = unread job count (NSApp.dockTile.badgeLabel), recomputed on relevant changes.
- queue-auto-paused → critical notification + NSApp.requestUserAttention(.criticalRequest) + route to LLM Queue.
- jobhunt:// URL handling (onOpenURL) → Router (jobs/N). Observe the focus-bridge notification posted by the HTTP server (task-047) → raise/focus window + navigate.
- **Sparkle (DMG only, `#if !MAS_BUILD`):** integrate Sparkle 2 updater (appcast URL → GitHub Releases). MAS flavor omits Sparkle (App Store updates).

## Dependencies
Depends on task-045 (Router/shell), task-044 (events), task-047 (focus bridge), task-041 (availability events). Sparkle appcast publishing is wired in the DMG release task (AE).

## Tests (AppUITests + unit)
- Unit-test notification gating decisions (high-fit always; suppress on big batch; critical bounce on auto-pause). Deep-link routing test. Manual checklist for dock badge + Sparkle check (documented).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Notifications reproduce electron/main.js rules (job-ready high-fit emphasis, batch suppression, unavailable, ai-errors, queue-auto-paused critical+bounce)
- [ ] #2 Dock badge shows unread count and updates on changes
- [ ] #3 jobhunt://jobs/N deep links + /api/app/focus bridge focus the window and navigate
- [ ] #4 Sparkle 2 wired for DMG flavor only (#if !MAS_BUILD); MAS omits it
- [ ] #5 Unit tests for notification gating + deep-link routing; documented manual checklist for badge/Sparkle
<!-- AC:END -->
