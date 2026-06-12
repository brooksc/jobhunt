---
id: TASK-338
title: 'Extension preflight: Make GitHub issue link data sharing explicit'
status: Done
assignee: []
created_date: '2026-06-12 20:26'
updated_date: '2026-06-12 20:58'
labels:
  - audit
  - privacy
  - extension
  - ux
dependencies: []
references:
  - extension/capture.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The preflight dialog's Wrong data? link builds a GitHub issue URL containing the job URL and extracted preview fields. Clicking the link sends those query parameters to GitHub before issue submission, but the UI label does not clearly frame that external data transfer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The preflight UI clearly indicates that reporting capture issues opens GitHub and may include the job URL/preview fields.
- [ ] #2 The user can inspect or edit the report content before any issue is submitted.
- [ ] #3 Tests or manual QA verify the generated issue link contains only intended fields and no captured full description/resume text.
<!-- AC:END -->
