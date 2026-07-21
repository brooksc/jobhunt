#!/usr/bin/env bash
# Build Jobhunt without running it.
# Usage: ./scripts/build.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Jobhunt-DMG"
CONFIG="Debug-DMG"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Jobhunt-local"

# shellcheck source=scripts/ensure-xcode.sh
source "$REPO_ROOT/scripts/ensure-xcode.sh"

cd "$REPO_ROOT"

echo "→ Building $SCHEME ($CONFIG)..."
nice xcodebuild build \
    -project Jobhunt.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    | xcbeautify 2>/dev/null || xcodebuild build \
        -project Jobhunt.xcodeproj \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_ALLOWED=NO
