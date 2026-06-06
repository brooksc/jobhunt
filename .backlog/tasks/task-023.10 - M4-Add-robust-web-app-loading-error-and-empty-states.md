---
id: TASK-023.10
title: 'M4: Add robust web app loading error and empty states'
status: Done
assignee: []
created_date: '2026-05-27 18:10'
updated_date: '2026-05-28 20:38'
labels:
  - m4
  - web
  - ui-audit
  - resilience
dependencies: []
modified_files:
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/app.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/screens/sites.jsx
  - src/jobhunt/static/screens/duplicates.jsx
  - src/jobhunt/static/screens/needs.jsx
  - src/jobhunt/static/styles.css
  - tests/
parent_task_id: TASK-023
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Second audit source: `src/jobhunt/static/main.jsx`, `src/jobhunt/static/app.jsx`, all screen components. Current state: `main.jsx` fetches `/api/ui-data` once and silently falls back to empty arrays if the request fails; the user sees an apparently empty app rather than an error. There is no explicit loading state because the app mounts only after fetch completes. Several screens also lack useful empty states: Jobs renders an empty table body, Duplicates renders an empty wrapper with no message, Sites renders an empty table, and Needs Action can be empty because no next actions exist but does not explain how to create one. API JSON parsing for `extracted_json` happens in the mapper and can throw if malformed, potentially preventing the app from mounting.

Recommendation: Introduce a small boot state before mounting `JobhuntApp`: loading, loaded, and error. If `/api/ui-data` fails or mapping throws, render an app-styled error page with retry and health-check details. Add screen-specific empty states with supported next actions only. Harden extracted JSON parsing per row so one bad job cannot blank the whole app.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The app shows a loading state while `/api/ui-data` is being fetched or mapped.
- [ ] #2 If `/api/ui-data` fails, the app shows an error state with retry and does not silently show empty data.
- [ ] #3 Malformed `extracted_json` for one job does not prevent the rest of the app from rendering.
- [ ] #4 Jobs, Sites, Duplicates, and Needs Action screens each have clear empty states that do not imply unsupported actions.
- [ ] #5 Empty states link to real implemented actions only, or clearly state what is not configured yet.
- [ ] #6 Tests or manual verification cover API failure, malformed extracted JSON, and at least two empty screens.
<!-- AC:END -->
