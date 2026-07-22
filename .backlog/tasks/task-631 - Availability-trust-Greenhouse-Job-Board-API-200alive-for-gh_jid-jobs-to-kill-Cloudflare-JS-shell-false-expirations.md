---
id: TASK-631
title: >-
  Availability: trust Greenhouse Job Board API (200=alive) for gh_jid jobs to
  kill Cloudflare/JS-shell false expirations
status: In Progress
assignee: []
created_date: '2026-07-22 23:14'
labels:
  - availability
  - detection
  - greenhouse
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Career sites fronted by Cloudflare + a JS shell (Pinterest #122, Cribl #325, etc.) return a bot-challenge or a generic JS-shell to the availability checker, producing false "gone" candidates. These postings carry a Greenhouse gh_jid, and Greenhouse's PUBLIC Job Board API (boards-api.greenhouse.io/v1/boards/{board}/jobs/{gh_jid}, no API key) returns a clean 200/404.

Add a confirm-alive override in the gone-candidate path (findGoneJobs, which also backs the launch-time confirm-first pass): for a job whose capture/application URL carries a gh_jid, query the Greenhouse Job Board API using board tokens derived from the company name and career-site host; if any returns 200, treat the job as available and do NOT surface it as gone. Safe by construction — a 200 can only REMOVE a false positive; a 404 / no-match falls back to today's HTML heuristics, so a genuinely dead job is still caught. Requires no credentials.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A job carrying a Greenhouse gh_jid whose Job Board API returns 200 is treated as available and excluded from gone candidates, even when the career-site HTML would look gone
- [ ] #2 Board token is derived from the normalized company name and the career-site host (with common suffixes like 'careers'/'jobs' stripped); *.greenhouse.io URLs use the board in the path
- [ ] #3 A non-200 / no matching board falls back to the existing HTML availability logic (no new false negatives)
- [ ] #4 The Greenhouse call is bounded by a short timeout and a small number of board candidates
- [ ] #5 Focused tests: 200 overrides a would-be-gone HTML result; non-200 falls through; board-candidate derivation
<!-- AC:END -->
