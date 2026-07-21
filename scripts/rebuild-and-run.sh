#!/usr/bin/env bash
# Kill, rebuild, test, and launch Jobhunt.
# Usage: ./scripts/rebuild-and-run.sh [--skip-tests]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Jobhunt"
SCHEME="Jobhunt-DMG"
CONFIG="Debug-DMG"
SKIP_TESTS=false
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Jobhunt-local"

for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=true ;;
        *) echo "Usage: $0 [--skip-tests]" >&2; exit 1 ;;
    esac
done

# Make the direct `xcodebuild test` call below resilient to xcode-select pointing at Command Line
# Tools (build.sh sources this too, but it runs in a child process, so its DEVELOPER_DIR wouldn't
# reach the test step here).
# shellcheck source=scripts/ensure-xcode.sh
source "$REPO_ROOT/scripts/ensure-xcode.sh"

cd "$REPO_ROOT"

# 1. Kill any running instance
echo "→ Killing existing $APP_NAME processes..."
pkill -x "$APP_NAME" 2>/dev/null || true

# 2. Build (delegates to build.sh)
"$REPO_ROOT/scripts/build.sh"

# 3. Tests
if [ "$SKIP_TESTS" = false ]; then
    # Fast gate: CoreTests + ServerTests + MCPTests (~30s). Matches CI.
    # AppUITests and LLMEval are opt-in — run them separately before a release.
    echo "→ Running fast gate (CoreTests + ServerTests + MCPTests)..."
    COV_RESULT="$DERIVED_DATA/FastTests.xcresult"
    rm -rf "$COV_RESULT"
    # Pretty-print through xcbeautify only if it's installed; fall back to a plain
    # pass-through. set -o pipefail (set at top) makes a test failure abort the script,
    # so the gate is honoured and we never re-run the whole suite.
    if command -v xcbeautify >/dev/null 2>&1; then PRETTY=(xcbeautify); else PRETTY=(cat); fi
    nice xcodebuild test \
        -project Jobhunt.xcodeproj \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        -only-testing:CoreTests \
        -only-testing:ServerTests \
        -only-testing:MCPTests \
        -enableCodeCoverage YES \
        -resultBundlePath "$COV_RESULT" \
        CODE_SIGNING_ALLOWED=NO \
        | "${PRETTY[@]}"

    echo "→ Checking coverage floor..."
    "$REPO_ROOT/scripts/check-coverage.sh" "$COV_RESULT"

    # Extension Node tests (parity with CI). Skipped if extension/ or npm is absent.
    if [ -d "$REPO_ROOT/extension" ] && command -v npm >/dev/null 2>&1; then
        echo "→ Running extension Node tests..."
        npm test --prefix "$REPO_ROOT/extension"
    fi
fi

# 4. Find and launch
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIG/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "✗ Could not find built ${APP_NAME}.app at $APP_PATH" >&2
    exit 1
fi

echo "→ Launching $APP_PATH..."
open "$APP_PATH"
echo "✓ Done."
