---
id: TASK-023.15
title: 'M4: Normalize extracted field display values and fallbacks'
status: Done
assignee: []
created_date: '2026-05-27 18:11'
updated_date: '2026-05-31 23:20'
labels:
  - m4
  - web
  - ui-audit
  - presentation
dependencies: []
modified_files:
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/components.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/screens/detail.jsx
  - tests/
parent_task_id: TASK-023
priority: medium
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Most display normalization is implemented in the Node app. Remaining work is to harden salary/currency semantics and add regression coverage for mapping/fallback behavior across succeeded, pending, failed, and partial extraction rows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Employment type displays human-friendly labels such as `Full time` rather than raw enum values.
- [x] #2 Missing seniority/employment/remote/company values render consistently and do not create empty chips.
- [x] #3 Company fallback does not use page title as company in a way that mislabels failed extraction rows.
- [x] #4 Salary display does not imply USD or annual pay when those fields are missing or salary_note says otherwise.
- [x] #5 Source labels preserve enough host information to distinguish similar job boards, with full URL still available.
- [x] #6 Mapping behavior is covered by tests or documented fixture/manual checks for succeeded, pending, failed, and partial extraction rows.
<!-- AC:END -->
