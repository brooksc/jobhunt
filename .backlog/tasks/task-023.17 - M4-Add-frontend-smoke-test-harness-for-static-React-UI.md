---
id: TASK-023.17
title: 'M4: Add frontend smoke test harness for static React UI'
status: Done
assignee: []
created_date: '2026-05-27 18:11'
updated_date: '2026-05-31 17:31'
labels:
  - m4
  - web
  - ui-audit
  - testing
dependencies: []
modified_files:
  - tests/
  - pyproject.toml
  - src/jobhunt/static/
  - spec.md
parent_task_id: TASK-023
priority: medium
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Outstanding work: add a minimal Playwright smoke suite that starts app with seeded DB, validates no console/runtime errors, navigates all major routes, opens at least one detail panel, and performs one API-backed UI action.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A documented command runs browser smoke tests for the local web UI.
- [ ] #2 Smoke tests start against an isolated temporary DB or deterministic seeded fixture data.
- [ ] #3 Tests verify the app loads without console/runtime errors.
- [ ] #4 Tests navigate to Dashboard, Jobs, Sites, Duplicates, Settings, and at least one Job detail panel.
- [ ] #5 Tests exercise at least one API-backed UI action such as status update, add note, or export link.
- [ ] #6 The test harness is integrated into developer docs or project test instructions without making ordinary backend tests slow by default.
- [ ] #7 1
- [ ] #8 2
- [ ] #9 3
- [ ] #10 4
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented a Playwright-backed Node test harness in the Node/JS port. The smoke test starts a temp app/database, loads the Jobs screen in a real browser, verifies split salary columns render, selects multiple rows, and exercises bulk status editing. Run with npm run test:ui.
<!-- SECTION:NOTES:END -->
