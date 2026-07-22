---
id: TASK-635
title: >-
  Application-form preview via ATS ?questions=true (what the application will
  ask)
status: To Do
assignee: []
created_date: '2026-07-22 23:20'
labels:
  - greenhouse
  - job-detail
  - auto-apply
dependencies:
  - TASK-631
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Greenhouse's GET /v1/boards/{board}/jobs/{gh_jid}?questions=true returns the actual application form fields (required/optional, cover letter, essay questions, EEO, work-auth). Show a preview on the job — "this application asks for: cover letter + 3 essays + work auth" — so the user can gauge effort before starting, and prioritize. Pairs naturally with the Auto-Apply (Codex) prompt: it can be told the fields up front. Read-only; no submission.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A gh_jid job shows a preview of the application's questions/fields from the ATS API
- [ ] #2 The preview distinguishes required vs optional and highlights heavy items (essays, cover letter)
- [ ] #3 The field list can be fed into the Auto-Apply prompt context
- [ ] #4 Degrades gracefully when questions aren't available
<!-- AC:END -->
