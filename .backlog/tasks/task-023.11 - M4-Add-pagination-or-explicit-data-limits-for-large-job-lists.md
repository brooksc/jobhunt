---
id: TASK-023.11
title: 'M4: Add pagination or explicit data limits for large job lists'
status: Done
assignee: []
created_date: '2026-05-27 18:10'
updated_date: '2026-05-28 20:38'
labels:
  - m4
  - web
  - ui-audit
  - data
dependencies: []
modified_files:
  - src/jobhunt/api.py
  - src/jobhunt/db.py
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/screens/sites.jsx
  - tests/
parent_task_id: TASK-023
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Second audit source: `src/jobhunt/api.py`, `src/jobhunt/static/main.jsx`, `src/jobhunt/static/screens/jobs.jsx`, `src/jobhunt/static/screens/sites.jsx`. Current state: `/api/ui-data` silently limits jobs to 200 and site review rows to 100. The UI presents the data as the full local database, but there is no pagination, load-more control, total count, or warning that older rows are omitted. Jobs table filtering/searching operates only on the loaded subset, so results can be misleading once the database grows. CSV export uses a separate path and exports up to 10,000 dashboard jobs, so UI and export can disagree.

Recommendation: Either remove the arbitrary UI limits for M4 if local dataset size is expected to remain small, or implement server-side pagination/counts. A pragmatic version is to return `total_jobs`, `total_sites`, `limit`, and `offset` metadata plus a Load more control. If server-side filtering is deferred, clearly label filters as applying to loaded rows only when truncated.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `/api/ui-data` returns total counts and loaded counts for jobs and sites, or no longer silently truncates current data.
- [ ] #2 If data is truncated, the UI clearly indicates that only the newest N records are loaded.
- [ ] #3 Jobs table can load more records or paginate through the full database.
- [ ] #4 Search/filter behavior is documented in UI terms: either full-database server-side filtering or loaded-row filtering with a truncation warning.
- [ ] #5 CSV export and UI counts do not contradict each other without explanation.
- [ ] #6 Tests cover API count/limit metadata and load-more or no-limit behavior.
<!-- AC:END -->
