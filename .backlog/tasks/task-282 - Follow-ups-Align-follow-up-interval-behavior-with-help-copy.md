---
id: TASK-282
title: 'Follow-ups: Align follow-up interval behavior with help copy'
status: Done
assignee: []
created_date: '2026-06-12 03:36'
updated_date: '2026-06-12 03:58'
labels:
  - audit
  - follow-up
  - application-workflow
  - settings
dependencies: []
references:
  - app/Views/Help/HelpView.swift
  - app/Views/Detail/JobDetailView.swift
  - core/Settings/SettingsStore.swift
modified_files:
  - app/Views/Help/HelpView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help describes the follow-up interval as the default number of days before a follow-up is due after applying, but the setting is only used to prefill the manual Set Next Action sheet. Either automate post-apply follow-up creation or update the help/settings copy to reflect manual behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Applying to a job creates or offers to create a follow-up using followupDefaultDays, or the UI copy no longer implies automatic post-apply reminders.
- [x] #2 Settings/help text match actual behavior.
- [x] #3 Tests cover follow-up due-date calculation for the chosen workflow.
<!-- AC:END -->
