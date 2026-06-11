#!/usr/bin/env bash
# Run XCUITest screenshot suite with automatic database backup.
# Usage: scripts/screenshot-tests.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DB_DIR="$HOME/Library/Application Support/Jobhunt"
DB="$DB_DIR/jobhunt.store"
BACKUP="$DB_DIR/jobhunt.store.pre-screenshots-$(date +%Y%m%d-%H%M%S).bak"
SCREENSHOTS="$REPO/screenshots"

# 1. Back up production database before touching the app via UI tests.
if [[ -f "$DB" ]]; then
    cp "$DB" "$BACKUP"
    echo "✓ Database backed up to $(basename "$BACKUP")"
else
    echo "⚠ No database found at $DB — continuing without backup"
fi

# 2. Run the screenshot tests.
echo "→ Running screenshot tests…"
LOG=$(mktemp)
nice xcodebuild test \
    -project "$REPO/Jobhunt.xcodeproj" \
    -scheme AppUITests \
    -destination 'platform=macOS' \
    -derivedDataPath "$REPO/build" \
    -only-testing AppUITests/ScreenshotTests \
    2>&1 | tee "$LOG"

# 3. Extract the screenshot directory path from test output and copy to project.
CONTAINER_DIR=$(grep 'SCREENSHOT_DIR:' "$LOG" | head -1 | sed 's/.*SCREENSHOT_DIR: //')
if [[ -n "$CONTAINER_DIR" && -d "$CONTAINER_DIR" ]]; then
    DEST="$SCREENSHOTS/$(basename "$CONTAINER_DIR")"
    mkdir -p "$DEST"
    cp "$CONTAINER_DIR"/*.png "$DEST/" 2>/dev/null || true
    COUNT=$(ls "$DEST"/*.png 2>/dev/null | wc -l | tr -d ' ')
    echo "✓ $COUNT screenshots saved to screenshots/$(basename "$CONTAINER_DIR")/"
else
    echo "⚠ Could not find screenshot directory in test output"
fi

rm -f "$LOG"

# 4. Remove old auto-backups (keep 5 most recent screenshot backups).
ls -t "$DB_DIR"/jobhunt.store.pre-screenshots-*.bak 2>/dev/null | tail -n +6 | xargs rm -f || true
