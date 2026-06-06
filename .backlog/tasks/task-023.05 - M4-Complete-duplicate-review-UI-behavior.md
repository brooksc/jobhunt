---
id: TASK-023.05
title: 'M4: Complete duplicate review UI behavior'
status: Done
assignee: []
created_date: '2026-05-27 18:06'
updated_date: '2026-06-01 04:11'
labels:
  - m4
  - web
  - ui-audit
  - duplicates
dependencies: []
modified_files:
  - src/jobhunt/static/screens/duplicates.jsx
  - src/jobhunt/static/main.jsx
  - src/jobhunt/api.py
  - src/jobhunt/db.py
  - tests/
parent_task_id: TASK-023
priority: medium
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Duplicate review is mostly implemented in the Node app: search filters groups, each group tracks a selected keep job, group merge uses that selected job, compare mode supports selecting candidates in groups larger than two, and actions show toast feedback. Remaining work is to remove remaining page reloads, verify explanatory copy, and add regression tests for duplicate decisions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Duplicate search filters groups by company, title, source URL, or hash, or the search box is removed.
- [ ] #2 Unsupported `Group by` and `Min similarity` controls are removed or implemented against real duplicate metadata.
- [x] #3 Each duplicate group tracks one selected keep job; checkboxes/radios reflect and control that state.
- [x] #4 Group-level Merge keeps the selected job, not always the first row.
- [x] #5 Compare mode handles groups with more than two candidates or clearly constrains comparison to selected candidates.
- [x] #6 Merge/Not duplicate actions show confirmation and success/error feedback in app UI, not raw alerts only.
- [ ] #7 Footer/explanatory text accurately describes what the DB does after merge; source alias preservation is implemented or the claim is removed.
- [ ] #8 Tests cover duplicate decision behavior for chosen keep job and groups with more than two candidates.
- [ ] #9 2
- [ ] #10 7
- [ ] #11 8
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed duplicate-page hard reloads in favor of app data refresh through JH_API.decideDuplicate, corrected footer copy to say non-kept jobs are archived with a reference to the kept job, confirmed unsupported Group by/Min similarity controls are absent, and added DB regression tests for selected keep job behavior and duplicate groups larger than two candidates.
<!-- SECTION:NOTES:END -->
