---
id: TASK-334
title: 'Local server: Restrict extension routes to the Jobhunt extension origin'
status: To Do
assignee: []
created_date: '2026-06-12 20:26'
labels:
  - audit
  - security
  - server
  - extension
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - extension/manifest.json
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobhuntServer currently treats any Origin beginning with chrome-extension:// as trusted and reflects it in CORS. Any installed extension with localhost access could call capture, site-review, URL lookup, or focus routes. Restrict extension-only routes and CORS reflection to the known Jobhunt extension ID(s) or add an extension auth token/handshake.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Only the Jobhunt extension origin or an authenticated extension client can call extension-only routes.
- [ ] #2 CORS headers are not reflected for arbitrary chrome-extension:// origins.
- [ ] #3 Server tests cover allowed Jobhunt origin, arbitrary extension origin rejection, and non-extension origin rejection.
<!-- AC:END -->
