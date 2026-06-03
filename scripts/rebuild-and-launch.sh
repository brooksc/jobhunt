#!/bin/sh
# Kill any running Jobhunt Electron app, run tests, rebuild, and relaunch.
# Usage: ./scripts/rebuild-and-launch.sh [--skip-tests]
set -e

cd "$(dirname "$0")/.."

SKIP_TESTS=0
if [ "${1:-}" = "--skip-tests" ]; then
  SKIP_TESTS=1
fi

# ------------------------------------------------------------------
# 1. Kill running Jobhunt app
# ------------------------------------------------------------------
if pgrep -x "Jobhunt" > /dev/null 2>&1; then
  echo "Stopping running Jobhunt app..."
  pkill -x "Jobhunt" || true
  sleep 1
fi

# ------------------------------------------------------------------
# 2. Lint
# ------------------------------------------------------------------
echo ""
echo "Linting..."
nice npm run lint

# ------------------------------------------------------------------
# 3. Tests (skip electron smoke — requires a built app)
# ------------------------------------------------------------------
if [ "$SKIP_TESTS" = "0" ]; then
  echo ""
  echo "Running tests..."
  nice node --test \
    tests/unit/availability.test.js \
    tests/unit/cleaning.test.js \
    tests/unit/extract.test.js \
    tests/unit/extension_capture.test.js \
    tests/unit/extension_csv.test.js \
    tests/unit/extension_manifest.test.js \
    tests/unit/extension_retry_queue.test.js \
    tests/integration/db.test.js \
    tests/integration/api.test.js \
    tests/integration/mcp.test.js
fi

# ------------------------------------------------------------------
# 4. Build Electron app
# ------------------------------------------------------------------
echo ""
echo "Building Electron app..."
nice ./node_modules/.bin/electron-builder --dir --mac

# ------------------------------------------------------------------
# 5. Launch
# ------------------------------------------------------------------
echo ""
echo "Launching Jobhunt..."
open dist/mac-arm64/Jobhunt.app

echo "Done."
