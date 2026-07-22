---
id: TASK-636
title: 'Generalize authoritative ATS lookups beyond Greenhouse (Lever, Ashby, Workday)'
status: To Do
assignee: []
created_date: '2026-07-22 23:20'
labels:
  - ats
  - availability
  - architecture
dependencies:
  - TASK-631
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-631 uses the Greenhouse public Job Board API as an authoritative availability/metadata source. The same pattern generalizes to the other ATSes we already detect posting ids for: Lever (api.lever.co/v0/postings/{company}[/{id}]), Ashby (public posting API), and Workday (the CXS endpoint we already query for liveness). Introduce a small provider abstraction — "given an ATS id + company/host, return {alive, content, title, location, updated_at, questions}" — so availability, description-refresh (TASK-632), freshness (TASK-633), company-roles (TASK-634), and form-preview (TASK-635) all work across providers instead of Greenhouse-only. Keep it public-source / no-credential; each provider is best-effort with graceful fallback to today's HTML behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A provider protocol abstracts authoritative lookup (alive/content/metadata) keyed by ATS id + company/host
- [ ] #2 Greenhouse (existing), Lever, and Ashby are implemented as providers; Workday liveness is folded in
- [ ] #3 Availability + the metadata features consume the abstraction rather than Greenhouse-specific code
- [ ] #4 Each provider is public/no-key, bounded by timeouts, and falls back cleanly
<!-- AC:END -->
