#!/usr/bin/env bash
# Kill, rebuild, test, and launch Jobhunt.
# Usage: ./scripts/rebuild-and-run.sh [--skip-tests]
# -jobs 6 throughout: fanless 8-core MacBook Air. An uncapped build saturates every core,
# thermally throttles within minutes, and finishes slower than a capped one while making the
# GUI unusable. Leave two cores for the machine's owner.
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

# Resolve a tool at the version pinned in .mise.toml, falling back to PATH.
#
# Prefers `mise which` when mise is on PATH; otherwise reads the pin and looks in mise's install
# directory directly, because this script is often run from a non-interactive shell where mise's
# shims aren't activated. Echoes nothing when the tool can't be found at all, so callers can skip.
pinned_tool() {
    local tool="$1" version="" candidate=""

    if command -v mise >/dev/null 2>&1; then
        candidate="$(mise which "$tool" 2>/dev/null || true)"
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            echo "$candidate"
            return
        fi
    fi

    version="$(sed -n "s/^${tool}[[:space:]]*=[[:space:]]*\"\(.*\)\"/\1/p" "$REPO_ROOT/.mise.toml" 2>/dev/null | head -1)"
    if [ -n "$version" ]; then
        candidate="$(find "$HOME/.local/share/mise/installs/$tool/$version" -name "$tool" -type f -perm -u+x 2>/dev/null | head -1)"
        if [ -n "$candidate" ]; then
            echo "$candidate"
            return
        fi
        echo "warning: $tool $version (pinned) not installed — run 'mise install'" >&2
    fi

    command -v "$tool" 2>/dev/null || true
}


# 1. Kill any running instance
echo "→ Killing existing $APP_NAME processes..."
pkill -x "$APP_NAME" 2>/dev/null || true

# 2. Build (delegates to build.sh)
"$REPO_ROOT/scripts/build.sh"

# 3. Tests
if [ "$SKIP_TESTS" = false ]; then
    # SwiftLint first — CI's "Swift Build" fails on lint violations, and this gate previously didn't
    # run the linter, so a lint error could reach main and fail every push. set -o pipefail aborts
    # here on a violation. Skipped only if swiftlint isn't installed.
    # Resolve the MISE-PINNED binaries rather than trusting PATH.
    #
    # These steps exist to match CI, and CI uses the versions pinned in .mise.toml. A different
    # SwiftFormat on PATH does not merely disagree — Homebrew's build reports ~108 files needing
    # formatting where the pinned one reports none, and under `set -e` that aborts this script before
    # it ever builds. docs/backlog-triage-2026-08.md records the same mismatch keeping main red for a
    # week. "Matches CI" has to mean the same binary, not the same command name.
    SWIFTLINT_BIN="$(pinned_tool swiftlint)"
    SWIFTFORMAT_BIN="$(pinned_tool swiftformat)"

    if [ -n "$SWIFTLINT_BIN" ]; then
        echo "→ Running SwiftLint ($("$SWIFTLINT_BIN" version 2>/dev/null || echo "?"), matches CI)..."
        "$SWIFTLINT_BIN" lint --quiet
    fi
    if [ -n "$SWIFTFORMAT_BIN" ]; then
        echo "→ Running SwiftFormat --lint ($("$SWIFTFORMAT_BIN" --version 2>/dev/null || echo "?"), matches CI)..."
        "$SWIFTFORMAT_BIN" app core server/swift mcp/swift tests --lint
    fi

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
        -jobs 6 \
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
