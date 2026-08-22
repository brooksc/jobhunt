#!/usr/bin/env bash
# Build Jobhunt without running it.
# Usage: ./scripts/build.sh
# -jobs 6 throughout: fanless 8-core MacBook Air. An uncapped build saturates every core,
# thermally throttles within minutes, and finishes slower than a capped one while making the
# GUI unusable. Leave two cores for the machine's owner.
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
        -jobs 6 \
    -project Jobhunt.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    | xcbeautify 2>/dev/null || xcodebuild build \
        -jobs 6 \
        -project Jobhunt.xcodeproj \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_ALLOWED=NO
