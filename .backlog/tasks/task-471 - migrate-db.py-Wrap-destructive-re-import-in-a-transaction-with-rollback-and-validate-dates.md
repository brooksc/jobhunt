---
id: TASK-471
title: >-
  migrate-db.py: Wrap destructive re-import in a transaction with rollback and
  validate dates
status: To Do
assignee: []
created_date: '2026-06-15 03:38'
labels:
  - bug
  - data-safety
  - scripts
dependencies: []
references:
  - scripts/migrate-db.py
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`scripts/migrate-db.py:96-233` performs a full destructive re-import: it deletes ZJOB/ZCAPTURE/etc. then re-inserts row-by-row, only calling `new.commit()` at line 283. Any exception (e.g. a bad row) aborts the script with the deletes already buffered and the connection abandoned without rollback, leaving the user to manually restore from `.pre-migration-bak`. Separately, `to_cd()` returns `None` on any unparseable date and those NULLs flow silently into NOT-NULL CoreData date columns. Fix: wrap the whole mutation in `try/except` calling `new.rollback()` (or `with new:`), print the restore command on failure, and fail loudly when `to_cd` returns None for a required column.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A mid-run failure rolls back all deletes/inserts (store left intact) and prints the restore command
- [ ] #2 Unparseable dates for required (NOT NULL) columns abort with a clear error rather than inserting NULL
- [ ] #3 Successful runs are unchanged
<!-- AC:END -->
