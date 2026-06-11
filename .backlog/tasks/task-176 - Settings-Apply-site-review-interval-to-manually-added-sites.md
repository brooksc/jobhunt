---
id: TASK-176
title: 'Settings: Apply site review interval to manually added sites'
status: To Do
assignee: []
created_date: '2026-06-11 22:12'
labels:
  - audit
  - settings
  - sites
  - workflow
dependencies: []
references:
  - app/Views/Settings/SettingsTab.swift
  - app/Views/Sites/AddSiteSheet.swift
  - core/Services/SiteService.swift
  - core/Models/Site.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The settings UI exposes `siteReviewIntervalDays`, but manual site creation calls `SiteService.createSite(url:name:)`, which relies on the `Site` model default interval instead of the configured setting. Manual sites should inherit the configured default interval or explicitly ask for an interval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Manually added sites use the configured default review interval or an explicitly selected interval.
- [ ] #2 The initial `nextReviewAt` schedule reflects the chosen interval.
- [ ] #3 Tests cover manual site creation with a non-default site review interval.
<!-- AC:END -->
