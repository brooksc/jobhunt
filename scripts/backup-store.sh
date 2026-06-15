#!/usr/bin/env bash
# backup-store.sh — make a consistent, single-file snapshot of the Jobhunt SwiftData store.
#
# Uses SQLite's online backup API (`.backup`), so it is safe to run WHILE the app is open — no
# need to quit, and the snapshot folds in the -wal automatically (the output is a single .store
# file with no -wal/-shm siblings to track).
#
# Usage:
#   ./scripts/backup-store.sh                 # back up the DMG (non-sandboxed) store
#   ./scripts/backup-store.sh --mas           # back up the Mac App Store (sandboxed) store
#   JOBHUNT_BACKUP_DIR=/Volumes/SSD/jh ./scripts/backup-store.sh   # custom destination
#
# Restore (DESTRUCTIVE — quit the app first):
#   1. Quit Jobhunt.
#   2. cd "~/Library/Application Support/Jobhunt"   (or the --mas container path printed below)
#   3. rm -f jobhunt.store jobhunt.store-shm jobhunt.store-wal
#   4. cp /path/to/jobhunt-YYYYMMDD-HHMMSS.store jobhunt.store
#   5. Relaunch Jobhunt.
set -euo pipefail

BUNDLE_ID="com.jobhunt-app.jobhunt"
KEEP="${JOBHUNT_BACKUP_KEEP:-30}"   # how many snapshots to retain
DEST_DIR="${JOBHUNT_BACKUP_DIR:-$HOME/Documents/jobhunt-backups}"
MIN_JOBS="${JOBHUNT_BACKUP_MIN_JOBS:-1}"   # refuse a snapshot with fewer jobs (0 = allow empty)

if [[ "${1:-}" == "--mas" ]]; then
  STORE="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/Jobhunt/jobhunt.store"
  LABEL="MAS (sandboxed)"
else
  STORE="$HOME/Library/Application Support/Jobhunt/jobhunt.store"
  LABEL="DMG (non-sandboxed)"
fi

if [[ ! -f "$STORE" ]]; then
  echo "Error: store not found for $LABEL build:" >&2
  echo "  $STORE" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
TS="$(date +%Y%m%d-%H%M%S)"
DEST="$DEST_DIR/jobhunt-$TS.store"

echo "Source: $STORE  [$LABEL]"
echo "Dest:   $DEST"

# Online backup — consistent even with the app running.
sqlite3 "$STORE" ".backup '$DEST'"

# Verify before trusting it.
CHECK="$(sqlite3 "$DEST" 'PRAGMA integrity_check;')"
if [[ "$CHECK" != "ok" ]]; then
  echo "Error: integrity check FAILED on the snapshot ($CHECK) — keeping it for inspection." >&2
  exit 1
fi

JOBS="$(sqlite3 "$DEST" 'SELECT COUNT(*) FROM ZJOB;')"
SIZE="$(du -h "$DEST" | cut -f1)"

# TASK-473: content sanity gate. An empty store passes integrity_check but is not a meaningful
# backup; keeping it would let it rotate a real backup out (rotation prunes purely by mtime). Refuse
# a suspect snapshot and remove it BEFORE rotation, so a single bad run can't erode retention.
if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || (( JOBS < MIN_JOBS )); then
  echo "Error: snapshot has $JOBS job(s) (need >= $MIN_JOBS) — refusing to keep it or rotate a good backup out." >&2
  echo "       (Set JOBHUNT_BACKUP_MIN_JOBS=0 to allow empty snapshots, e.g. on a fresh install.)" >&2
  rm -f "$DEST"
  exit 1
fi

echo "OK: integrity ok, $JOBS jobs, $SIZE"

# Rotation: keep the newest $KEEP snapshots. Only reached once the snapshot passed the sanity gate.
COUNT="$(ls -1 "$DEST_DIR"/jobhunt-*.store 2>/dev/null | wc -l | tr -d ' ')"
if (( COUNT > KEEP )); then
  ls -1t "$DEST_DIR"/jobhunt-*.store | tail -n +"$((KEEP + 1))" | while read -r old; do
    echo "Pruning old backup: $(basename "$old")"
    rm -f "$old"
  done
fi
