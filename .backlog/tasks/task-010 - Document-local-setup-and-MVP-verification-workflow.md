---
id: TASK-010
title: Document local setup and MVP verification workflow
status: Done
assignee: []
created_date: '2026-05-27 04:36'
updated_date: '2026-05-31 23:57'
labels:
  - m5-polish
  - docs
dependencies:
  - TASK-004
  - TASK-008
priority: medium
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create concise operator docs for the current Node implementation. `CLAUDE.md` has agent-oriented notes, but there is still no user-facing README covering install, run, extension setup, LM Studio, verification, runtime data paths, export, and troubleshooting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 README explains Node/npm dependency installation and required Node version.
- [x] #2 README explains `npm start`, `npm run serve:once`, `/health`, and the supervised restart behavior.
- [x] #3 README explains runtime data paths under `~/.config/jobhunt`, including DB and logs.
- [x] #4 README explains how to load the Chrome extension unpacked and verify capture/retry behavior.
- [x] #5 README explains LM Studio configuration, structured output expectations, and queue/debug logging basics.
- [x] #6 README documents CSV export and the standard verification commands: `npm test`, `npm run lint`, `npm run typecheck`.
<!-- AC:END -->
