---
id: TASK-473
title: 'backup-store.sh: Add content sanity gate before rotating snapshots'
status: Done
assignee: []
created_date: '2026-06-15 03:39'
updated_date: '2026-06-15 06:51'
labels:
  - bug
  - data-safety
  - scripts
dependencies: []
references:
  - scripts/backup-store.sh
modified_files:
  - scripts/backup-store.sh
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`scripts/backup-store.sh` rotation keeps the newest $KEEP snapshots by mtime (`ls -1t`, lines 60-66) with no content check. If a future run produces a smaller/corrupt-but-integrity-ok snapshot (e.g. pointed at the wrong/empty store via JOBHUNT_BACKUP_DIR mixups or an empty container), it still counts toward $KEEP and pushes the oldest good backup out. The `-f "$STORE"` existence check (line 33) passes even for a leftover zero-byte store, and the ZJOB count print (line 56) is informational with no minimum-rows gate. Fix: refuse to proceed if ZJOB count is 0 (or below a floor), and/or only count content-sane snapshots toward rotation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A snapshot with 0 jobs is refused (not written, not rotated in)
- [ ] #2 Rotation never evicts a good backup in favor of a suspect/empty one
- [ ] #3 A normal populated store backs up and rotates as before
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
backup-store.sh now applies a content sanity gate after the integrity check: if the snapshot has fewer than JOBHUNT_BACKUP_MIN_JOBS jobs (default 1; an empty store passes integrity_check but isn't a meaningful backup), it errors, removes the suspect snapshot, and exits BEFORE rotation (AC#1) — so a single empty/suspect run can't count toward $KEEP and rotate a real backup out (AC#2). JOBHUNT_BACKUP_MIN_JOBS=0 allows empty snapshots (e.g. fresh install). A normal populated store backs up and rotates exactly as before (AC#3). bash -n clean.
<!-- SECTION:FINAL_SUMMARY:END -->
