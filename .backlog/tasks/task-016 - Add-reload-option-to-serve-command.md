---
id: TASK-016
title: Add reload option to serve command
status: Done
assignee: []
created_date: '2026-05-27 05:49'
updated_date: '2026-05-27 05:50'
labels:
  - m5-polish
  - server
  - developer-experience
dependencies: []
modified_files:
  - src/jobhunt/cli.py
  - tests/test_cli.py
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a development reload option to the local server command so code changes restart the FastAPI app automatically during iteration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `jobhunt serve --reload` is accepted by the CLI
- [x] #2 The serve command passes reload through to Uvicorn
- [x] #3 Existing serve behavior remains unchanged when reload is omitted
- [x] #4 Focused tests or command checks continue to pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added `--reload/--no-reload` to the serve command. Reload mode uses Uvicorn's import string `jobhunt.api:app`, which is required for reload support. The command rejects combining `--reload` with `--db-path` because the reload worker imports the global app and would not receive the injected path.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added development reload support to the serve command. `jobhunt serve --reload` is now accepted and passes reload mode through to Uvicorn while the default non-reload path remains unchanged. Tests cover help output and the unsupported reload/db-path combination.
<!-- SECTION:FINAL_SUMMARY:END -->
