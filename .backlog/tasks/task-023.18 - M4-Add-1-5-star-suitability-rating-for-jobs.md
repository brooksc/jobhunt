---
id: TASK-023.18
title: 'M4: Add 1-5 star suitability rating for jobs'
status: Done
assignee: []
created_date: '2026-05-27 18:39'
updated_date: '2026-05-28 20:38'
labels:
  - m4
  - web
  - ui-audit
  - jobs
  - crud
dependencies: []
modified_files:
  - src/jobhunt/db.py
  - src/jobhunt/api.py
  - src/jobhunt/models.py
  - src/jobhunt/export.py
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/screens/detail.jsx
  - src/jobhunt/static/components.jsx
  - tests/
parent_task_id: TASK-023
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a user-controlled job suitability rating so the user can mark how well a job fits them, from 1 to 5 stars where 5 is the strongest fit. This is distinct from workflow status (`saved`, `applied`, `rejected`, etc.) and should be editable independently from extracted LLM data. The rating should help sort/filter the job list and quickly identify high-priority opportunities.

Recommended implementation: add a nullable integer column such as `jobs.rating` with validation range 1-5. Expose it through `/api/ui-data`, CSV export if appropriate, and a PATCH endpoint for updating a job rating. In the UI, show star controls in the Jobs table and job detail panel. Use an accessible button/radio pattern rather than only decorative stars. Persist changes immediately or through an explicit save affordance, but avoid browser `prompt()` scaffolding.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jobs can store a nullable rating from 1 to 5, with 5 representing the most suitable job.
- [ ] #2 Existing jobs migrate with no rating rather than a default rating.
- [ ] #3 API data includes each job rating, and invalid ratings outside 1-5 are rejected.
- [ ] #4 The Jobs table displays each job's rating and supports sorting/filtering by rating.
- [ ] #5 The job detail panel allows setting, changing, and clearing the rating without affecting workflow status or extracted fields.
- [ ] #6 Rating changes persist across reloads.
- [ ] #7 CSV export includes the rating, or the task documents a product decision to exclude it.
- [ ] #8 Tests cover schema migration, API update validation, UI data serialization, and export behavior if included.
<!-- AC:END -->
