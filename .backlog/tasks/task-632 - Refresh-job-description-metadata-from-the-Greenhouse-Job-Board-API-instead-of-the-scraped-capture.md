---
id: TASK-632
title: >-
  Refresh job description + metadata from the Greenhouse Job Board API instead
  of the scraped capture
status: To Do
assignee: []
created_date: '2026-07-22 23:20'
labels:
  - greenhouse
  - extraction
  - data-quality
dependencies:
  - TASK-631
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
For jobs carrying a Greenhouse gh_jid, the public Job Board API (boards-api.greenhouse.io/v1/boards/{board}/jobs/{gh_jid}, no key) returns clean, complete fields — full `content` (description HTML), `title`, `location.name`, `departments`, `offices`, `updated_at`, `absolute_url` — far more reliable than the Cloudflare/JS-shell career-site capture we currently scrape. Offer a "refresh from source" that pulls the canonical content and re-runs extraction/fit on a complete, clean description, and backfills structured location. Reuse the board-token derivation from TASK-631. Keep it explicit/opt-in per job (or a batch action) so it doesn't silently overwrite user edits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A gh_jid job can be refreshed from the Greenhouse API, replacing/augmenting the captured description with the canonical `content`
- [ ] #2 Structured location and other clean fields (title, departments) are backfilled without clobbering manual overrides
- [ ] #3 Extraction/fit can be re-run on the refreshed description
- [ ] #4 Falls back gracefully when the board can't be resolved or the API is unreachable
<!-- AC:END -->
