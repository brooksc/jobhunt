---
id: TASK-218
title: >-
  Privacy: Replace substring custom-endpoint locality checks with exact URL host
  validation
status: Done
assignee: []
created_date: '2026-06-12 01:04'
updated_date: '2026-06-12 02:00'
labels:
  - privacy
  - settings
  - security
dependencies: []
references:
  - core/Settings/ConsentHelper.swift
  - app/Views/Settings/SettingsView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Custom endpoint consent/API-key handling currently classifies local endpoints using substring checks, and SettingsView uses a different rule than ConsentHelper. Replace this with one shared URL parser that validates exact loopback hosts/IPs only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Loopback detection parses URLs and validates the normalized host exactly.
- [ ] #2 Remote hosts containing strings like localhost or 127.0.0.1 are not treated as local.
- [ ] #3 Settings UI and background consent enforcement use the same locality helper.
- [ ] #4 IPv4, IPv6 loopback, localhost, malformed URLs, and 0.0.0.0 cases are covered by tests.
<!-- AC:END -->
