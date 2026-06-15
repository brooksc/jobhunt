---
id: TASK-471
title: >-
  migrate-db.py: Wrap destructive re-import in a transaction with rollback and
  validate dates
status: Done
assignee: []
created_date: '2026-06-15 03:38'
updated_date: '2026-06-15 06:51'
labels:
  - bug
  - data-safety
  - scripts
dependencies: []
references:
  - scripts/migrate-db.py
modified_files:
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
to_cd now raises ValueError on a non-empty but unparseable date (empty/None still returns None for legitimately-absent optional dates) — preventing the silent NULL into NOT-NULL CoreData date columns (created_at/updated_at/captured_at) that crashed the app at read time (AC#2). The destructive re-import runs in a single sqlite3 transaction with no intermediate commit, so any exception leaves it uncommitted (auto-rolled-back on process exit — the store is never left half-wiped); the __main__ entry point now wraps migrate() to clearly report "failed and was rolled back — no changes committed" and print the exact restore command (cp BACKUP NEW_STORE) (AC#1). py_compile clean. Successful runs unchanged (AC#3).
<!-- SECTION:FINAL_SUMMARY:END -->
