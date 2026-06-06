---
id: TASK-023.08
title: 'M4: Make dashboard cards and status indicators reflect real workflows'
status: Done
assignee: []
created_date: '2026-05-27 18:06'
updated_date: '2026-05-31 04:41'
labels:
  - m4
  - web
  - ui-audit
  - dashboard
dependencies:
  - TASK-023.03
  - TASK-023.06
modified_files:
  - src/jobhunt/static/screens/dashboard.jsx
  - src/jobhunt/static/shell.jsx
  - src/jobhunt/static/app.jsx
  - src/jobhunt/api.py
  - src/jobhunt/db.py
  - tests/
parent_task_id: TASK-023
priority: medium
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Outstanding work: align dashboard cards and actions with real persisted workflows (follow-ups, extraction queue/process, status transitions), and remove or source service/extension/LLM health labels from actual checks instead of hardcoded strings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dashboard follow-up card uses persisted follow-up data and `Done` completes the action through the follow-up API.
- [x] #2 Dashboard extraction retry provides feedback and either processes the job immediately or opens the global extraction progress dialog.
- [x] #3 Dashboard metrics match `/api/ui-data` and update correctly after actions without misleading stale counts.
- [x] #4 Sidebar service/extension/LM Studio statuses are based on real health/config/last-seen data or the hardcoded claims are removed.
- [x] #5 Dashboard empty states provide relevant actions where a real action exists, without implying unsupported workflows.
- [ ] #6 Tests cover metrics for follow-ups/extractions and at least one dashboard-triggered action path.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented in the Node app. Dashboard cards now use live jobs/sites/queue/follow-up data and wire actions through the app APIs with toast feedback. Remaining dashboard regression coverage is tracked under the frontend smoke/test backlog.
<!-- SECTION:FINAL_SUMMARY:END -->
