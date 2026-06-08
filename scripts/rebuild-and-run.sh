#!/usr/bin/env bash
# Kill, rebuild, test, and launch Jobhunt.
# Usage: ./scripts/rebuild-and-run.sh [--skip-tests]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Jobhunt-DMG"
CONFIG="Debug-DMG"
APP_NAME="Jobhunt"
SKIP_TESTS=false

for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=true ;;
        *) echo "Usage: $0 [--skip-tests]" >&2; exit 1 ;;
    esac
done

cd "$REPO_ROOT"

# 1. Kill any running instance
echo "→ Killing existing $APP_NAME processes..."
pkill -x "$APP_NAME" 2>/dev/null || true

# 2. Build
echo "→ Building $SCHEME ($CONFIG)..."
nice xcodebuild build \
    -project Jobhunt.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    | xcbeautify 2>/dev/null || xcodebuild build \
        -project Jobhunt.xcodeproj \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO

# 3. Tests
if [ "$SKIP_TESTS" = false ]; then
    echo "→ Running tests..."
    nice xcodebuild test \
        -project Jobhunt.xcodeproj \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination 'platform=macOS' \
        -only-testing:CoreTests \
        CODE_SIGNING_ALLOWED=NO \
        | xcbeautify 2>/dev/null || xcodebuild test \
            -project Jobhunt.xcodeproj \
            -scheme "$SCHEME" \
            -configuration "$CONFIG" \
            -destination 'platform=macOS' \
            -only-testing:CoreTests \
            CODE_SIGNING_ALLOWED=NO
fi

# 4. Find and launch
APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData \
    -name "${APP_NAME}.app" \
    -path "*/${CONFIG}/${APP_NAME}.app" \
    -maxdepth 8 2>/dev/null | head -1)"

if [ -z "$APP_PATH" ]; then
    echo "✗ Could not find built ${APP_NAME}.app" >&2
    exit 1
fi

echo "→ Launching $APP_PATH..."
open "$APP_PATH"
echo "✓ Done."
