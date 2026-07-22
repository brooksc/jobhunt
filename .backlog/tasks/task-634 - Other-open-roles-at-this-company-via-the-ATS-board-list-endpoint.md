---
id: TASK-634
title: '"Other open roles at this company" via the ATS board list endpoint'
status: To Do
assignee: []
created_date: '2026-07-22 23:20'
labels:
  - greenhouse
  - discovery
  - job-detail
dependencies:
  - TASK-631
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Greenhouse board list endpoint (GET /v1/boards/{board}/jobs, no key) returns every open posting for a company. On a job whose company uses Greenhouse (board derivable via TASK-631), offer "other open roles at {company}" — list current postings, optionally filtered to similar titles/locations, with one-click add to the New funnel. A lightweight precursor to full discovery (DRAFT-001) scoped to a single already-known company. Lever/Ashby have analogous list endpoints.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On a gh_jid job, the app can list the company's other current open roles from the ATS board API
- [ ] #2 Results can be filtered (e.g. similar title/location) and added to New with source provenance
- [ ] #3 Respects existing URL/duplicate-resolution policy so re-adds don't create dupes
- [ ] #4 No credentials required; bounded timeouts + rate limiting
<!-- AC:END -->
