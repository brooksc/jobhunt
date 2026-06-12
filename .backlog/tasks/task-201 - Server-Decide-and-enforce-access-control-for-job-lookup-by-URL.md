---
id: TASK-201
title: 'Server: Decide and enforce access control for job lookup by URL'
status: To Do
assignee: []
created_date: '2026-06-12 00:16'
labels:
  - server
  - api
  - security
  - extension
  - audit
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - extension/service_worker.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The /api/jobs/by-url route exposes job-number lookup by source URL without the chrome-extension origin check used by the mutating extension routes. This may be intended local metadata, but the boundary is currently inconsistent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The intended access model for /api/jobs/by-url is documented.
- [ ] #2 If extension-only, the route requires the same chrome-extension origin gate as related extension routes.
- [ ] #3 Server tests cover allowed and rejected lookup requests.
<!-- AC:END -->
