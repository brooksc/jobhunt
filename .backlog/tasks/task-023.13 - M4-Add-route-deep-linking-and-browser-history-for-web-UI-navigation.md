---
id: TASK-023.13
title: 'M4: Add route deep-linking and browser history for web UI navigation'
status: Done
assignee: []
created_date: '2026-05-27 18:10'
updated_date: '2026-05-28 20:38'
labels:
  - m4
  - web
  - ui-audit
  - navigation
dependencies: []
modified_files:
  - src/jobhunt/static/app.jsx
  - src/jobhunt/static/shell.jsx
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/screens/detail.jsx
  - src/jobhunt/static/styles.css
parent_task_id: TASK-023
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Second audit source: `src/jobhunt/static/app.jsx`, `src/jobhunt/static/shell.jsx`, `src/jobhunt/static/screens/jobs.jsx`, `src/jobhunt/static/screens/detail.jsx`. Current state: route and selected job live only in React state. The app always mounts with `initialRoute="jobs"`; browser URL never changes when navigating to Dashboard/Sites/Duplicates/Settings or selecting a job. Reloading loses the current screen and selected detail panel. There is no way to link to `Job #4`, a specific duplicate group, or a settings page. Back/forward browser buttons do not navigate app state.

Recommendation: Add lightweight hash routing or History API routing. Keep it simple: `#/jobs`, `#/jobs/4` or `#/jobs/job_<uuid>`, `#/sites`, `#/duplicates`, `#/settings`. Since job numbers are user-facing, support job-number lookup in the route while preserving UUID internally. Update sidebar/topbar selection from route state and push history on navigation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Navigating between main sections updates the browser URL.
- [ ] #2 Reloading the page preserves the current section.
- [ ] #3 Selecting a job updates the URL and reload can reopen the same detail panel.
- [ ] #4 Job detail routes support user-facing job numbers, e.g. `#/jobs/4`, or clearly use another documented stable route format.
- [ ] #5 Browser back/forward buttons navigate section and job selection state.
- [ ] #6 Invalid routes and missing jobs show a clear app-level not-found state.
- [ ] #7 Manual verification or tests cover direct loading at Jobs, Sites, Settings, and a job detail route.
<!-- AC:END -->
