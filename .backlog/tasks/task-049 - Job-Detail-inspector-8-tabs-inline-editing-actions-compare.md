---
id: TASK-049
title: 'Job Detail inspector: 8 tabs, inline editing, actions, compare'
status: To Do
assignee: []
created_date: '2026-06-07 22:48'
labels:
  - swift-rewrite
  - ui
  - screen
milestone: m-1
dependencies:
  - TASK-045
  - TASK-046
  - TASK-044
  - TASK-036
  - TASK-039
documentation:
  - swift-plan.md
  - static/screens/detail.jsx
  - static/jd-parser.js
priority: high
ordinal: 2600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the right-side job detail inspector — 8 tabs of view/edit, inline field editing, follow-up actions, and duplicate compare.

## Read first
- swift-plan.md §10.2 #3 (Detail panel: 8 tabs + behaviors), §10.1 (inspector column + arrow-key nav), §8.5/§10.2#3 (Fit tab dimensions).
- Legacy static/screens/detail.jsx (1282 lines) — the authority for all tabs and edit behaviors.
- static/jd-parser.js (Raw tab block rendering — provided by task-036 JDParser).

## Implement (app/Views/Detail/)
- Inspector with tabs: Details (inline-editable company/title/location/work-mode/salary/employment/seniority/source; status chip; ⭐ rating 0–5; extraction-quality badge), Extracted data (structured fields + confidence), Fit score (overall + per-dimension breakdown + requirements met/not-met, per active resume), Summary, Requirements, Timeline (events), Raw (JDParser blocks), Compare (only when duplicate — side-by-side vs original, unmark/delete).
- Inline edit commits via JobService.updateFields; rating via setRating; notes via addNote; archive/delete; re-extract / fit-score triggers via the engine (task-044).
- Follow-up actions: create (note + due date), snooze N days, complete — via JobService.
- Keyboard: arrow keys move prev/next within the current Jobs list view; esc closes.

## Dependencies
Depends on task-045 (shell/inspector slot/components), task-046 (mutations), task-044 (extract/fit triggers), task-036 (JDParser), task-039 (fit score structure). Fills the third column opened by task S (Jobs).

## Tests (AppUITests)
- Edit a field and verify persistence; change status/rating; add a note→timeline; create+snooze+complete an action; switch all 8 tabs; arrow-key navigation; compare view for a duplicate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All 8 tabs implemented (Details/Extracted/Fit/Summary/Requirements/Timeline/Raw/Compare)
- [ ] #2 Inline editing of all Details fields persists via JobService; rating + status editable
- [ ] #3 Fit tab shows overall + per-dimension breakdown + requirements met/not-met per active resume
- [ ] #4 Re-extract and fit-score triggers enqueue via the engine; notes append to Timeline
- [ ] #5 Follow-up actions create/snooze/complete; Raw tab renders JDParser blocks; Compare works for duplicates
- [ ] #6 Arrow-key prev/next + esc-close; XCUITest covers edit/status/note/action/tabs/compare
<!-- AC:END -->
