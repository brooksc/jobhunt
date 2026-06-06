---
id: TASK-023.07
title: 'M4: Replace prompt/alert scaffolding with app-native dialogs and notifications'
status: Done
assignee: []
created_date: '2026-05-27 18:06'
updated_date: '2026-05-31 23:28'
labels:
  - m4
  - web
  - ui-audit
  - ux
dependencies: []
modified_files:
  - src/jobhunt/static/app.jsx
  - src/jobhunt/static/components.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/screens/detail.jsx
  - src/jobhunt/static/screens/needs.jsx
  - src/jobhunt/static/screens/sites.jsx
  - src/jobhunt/static/screens/duplicates.jsx
  - src/jobhunt/static/styles.css
parent_task_id: TASK-023
priority: medium
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Most prompt/alert scaffolding has been replaced with app dialogs and toasts in the Node app. Remaining work is to replace the few native browser confirmations/reloads still present, then add manual notes or smoke tests for dialog success/error paths.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A shared app modal/dialog primitive exists for text input, confirmation, and simple form submissions.
- [x] #2 A shared toast/notification primitive exists for success and error feedback.
- [x] #3 Existing prompt-based Add note flows use the app dialog and validate empty input before submission.
- [x] #4 Existing prompt-based status/site/date flows use app controls appropriate to the data type.
- [x] #5 API errors are shown in app UI instead of raw `alert()` for migrated flows.
- [x] #6 Migrated dialogs are keyboard accessible and close on Escape/cancel without side effects.
- [x] #7 No new product behavior is added beyond replacing current prompt/alert scaffolding.
- [x] #8 Manual verification notes or UI tests cover at least one dialog success path and one API error path.
<!-- AC:END -->
