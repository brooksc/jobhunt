---
id: TASK-086
title: >-
  Fix DashboardView: misleading Queue re-extraction button, Apply link
  double-fire, site row deep-link
status: Done
assignee: []
created_date: '2026-06-10 07:31'
updated_date: '2026-06-10 22:24'
labels:
  - bug
  - ui-audit
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HIGH: "Queue re-extraction" button only navigates to LLM Queue (`router.selectedSection = .llmQueue`). Nothing is actually queued. Label is actively misleading. Fix: actually enqueue re-extraction jobs, or rename button to "Go to LLM Queue".

MEDIUM: `Apply` Link nested inside row Button triggers both actions — inner Link opens browser AND outer Button navigates to job detail. Fix hit-test propagation.

LOW: Site row button navigates to `.sites` but doesn't set `router.selectedSiteID`, leaving user at top of Sites list.

Files: `app/Views/Dashboard/DashboardView.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queue re-extraction button either queues jobs or is renamed to reflect it only navigates
- [ ] #2 Clicking Apply link opens browser without also navigating to job detail
- [ ] #3 Clicking a site row in dashboard selects that specific site in the sidebar
<!-- AC:END -->
