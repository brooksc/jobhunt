---
id: TASK-633
title: Show posting freshness / repost signal from ATS updated_at + first_published
status: To Do
assignee: []
created_date: '2026-07-22 23:20'
labels:
  - greenhouse
  - job-detail
  - signal
dependencies:
  - TASK-631
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Greenhouse Job Board API (and Lever/Ashby equivalents) expose `updated_at` and `first_published` for a posting. Surface a freshness signal on the job — e.g. "posted 2 days ago", "reposted", "stale 6 weeks" — so the user can triage by how fresh/active a listing is. Derive from the authoritative ATS timestamp when a gh_jid (or other ATS id) is available; otherwise fall back to our capture date. Read-only; no writes to the posting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A gh_jid job shows an authoritative posted/updated date from the ATS API
- [ ] #2 A meaningful freshness label (fresh / stale / reposted) is derived and shown on the job
- [ ] #3 Falls back to capture date when no ATS timestamp is available
<!-- AC:END -->
