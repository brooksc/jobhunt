---
id: TASK-635
title: >-
  Application-form preview via ATS ?questions=true (what the application will
  ask)
status: Done
assignee: []
created_date: '2026-07-22 23:20'
updated_date: '2026-08-09 23:43'
labels:
  - greenhouse
  - job-detail
  - auto-apply
dependencies:
  - TASK-631
modified_files:
  - core/Services/ApplicationFormPreview.swift
  - core/Services/GreenhouseJobBoard.swift
  - core/Services/JobService+Greenhouse.swift
  - core/Services/JobPromptBuilder.swift
  - app/Views/Detail/ApplicationFormSheet.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Detail/JobPromptMenu.swift
  - tests/CoreTests/ApplicationFormPreviewTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Greenhouse's GET /v1/boards/{board}/jobs/{gh_jid}?questions=true returns the actual application form fields (required/optional, cover letter, essay questions, EEO, work-auth). Show a preview on the job — "this application asks for: cover letter + 3 essays + work auth" — so the user can gauge effort before starting, and prioritize. Pairs naturally with the Auto-Apply (Codex) prompt: it can be told the fields up front. Read-only; no submission.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A gh_jid job shows a preview of the application's questions/fields from the ATS API
- [x] #2 The preview distinguishes required vs optional and highlights heavy items (essays, cover letter)
- [x] #3 The field list can be fed into the Auto-Apply prompt context
- [x] #4 Degrades gracefully when questions aren't available
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`ApplicationFormPreview` in Core decodes `?questions=true`; `GreenhouseJobBoard.fetchApplicationForm` fetches it; `ApplicationFormSheet` shows it from a "What it asks for" button on gh_jid jobs.

#1 Live-verified against gitlab/8503792002: 13 questions, nested `fields` with types, mixed required/optional. The fixture is trimmed from that real response.

#2 Required vs optional is shown per row and counted in the header. The summary deliberately counts only *substantive* questions — name, email, LinkedIn and the résumé upload appear on every application, so counting them would make every posting look identical, which defeats the purpose. "Written answer" is judged on the field type plus label length: a `textarea` always, a free-text field with a label over 80 characters (on the board checked, the shortest essay prompt was 96 characters and the longest non-essay label was 20); a dropdown never, however long its label. A form asking only for a name and a résumé produces no summary at all.

#3 `JobPromptInput` gains `applicationForm`, rendered into the auto-apply prompt as a "What the application form asks for" section, so the agent knows the fields instead of discovering them by clicking. Fetched at copy time rather than stored — forms change, and a stale field list is worse guidance than none. Omitted entirely when unavailable, since an empty heading reads as "it asks for nothing".

#4 Absent questions decode to nil, and the sheet says the board doesn't publish its form rather than showing an empty one. Read-only throughout; nothing submits.

9 tests. Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 336 files, swiftformat 0.61.1 clean.

not verified: (visual) — sheet layout. The 80-character effort heuristic is calibrated on one board's questions; it may need adjusting once seen against more employers.
<!-- SECTION:FINAL_SUMMARY:END -->
