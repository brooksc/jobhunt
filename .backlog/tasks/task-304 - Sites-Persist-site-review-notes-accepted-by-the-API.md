---
id: TASK-304
title: 'Sites: Persist site review notes accepted by the API'
status: To Do
assignee: []
created_date: '2026-06-12 05:01'
labels:
  - audit
  - sites
  - api
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - core/Services/SiteService.swift
  - core/Models/SiteReview.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The site-review endpoint decodes note and passes it to SiteService, but SiteService never stores it on SiteReview.note or Site.note. API clients can send a note and receive success even though the note is dropped.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Site review notes are persisted to the intended model field or the API contract stops accepting notes.
- [ ] #2 Extension/HTTP review tests verify note persistence or explicit rejection.
- [ ] #3 Document the chosen note ownership between Site and SiteReview.
<!-- AC:END -->
