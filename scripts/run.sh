#!/usr/bin/env bash
# Kill and relaunch the already-built Jobhunt app without rebuilding.
set -euo pipefail

APP_NAME="Jobhunt"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Jobhunt-local"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-DMG/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "✗ No built app found at $APP_PATH" >&2
    echo "  Run scripts/rebuild-and-run.sh first." >&2
    exit 1
fi

echo "→ Killing existing $APP_NAME processes..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

echo "→ Launching $APP_PATH..."
open "$APP_PATH"
echo "✓ Done."
