---
id: DRAFT-004
title: 'Won''t Do: App Intents, Calendar, and Reminders integration'
status: Draft
assignee: []
created_date: '2026-07-22 20:59'
labels:
  - wont-do
  - product-direction
  - macos
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decision record: do not pursue broader macOS automation integrations right now. The deferred direction would expose safe JobHunt actions through App Intents/Shortcuts and optionally synchronize selected follow-ups with Calendar or Reminders.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A future implementation would expose only bounded domain actions rather than unrestricted data mutation.
- [ ] #2 Calendar and Reminders synchronization would be opt-in and idempotent.
<!-- AC:END -->
