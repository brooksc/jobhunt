#!/usr/bin/env bash
# Build JobhuntMigrator and print exactly where the executable landed.
#
# Why this exists (TASK-652): a stale migrator binary silently ran superseded logic against the live
# store — `--recompute-fit-mirrors` reported "0 corrected" while 206 mirrors were provably wrong. The
# cause was two DerivedData trees: scripts/rebuild-and-run.sh pins `-derivedDataPath .../Jobhunt-local`,
# while a bare `xcodebuild` writes to Xcode's default hashed path. Every build genuinely succeeded — it
# just wrote somewhere other than the binary being run, so the stale copy's mtime never moved.
#
# This script pins the SAME derived-data path as rebuild-and-run.sh and echoes the resulting binary, so
# the path you run is always the path you just built.
#
# Usage: ./scripts/build-migrator.sh [--config Debug-DMG|Release-DMG]
# -jobs 6 throughout: fanless 8-core MacBook Air. An uncapped build saturates every core,
# thermally throttles within minutes, and finishes slower than a capped one while making the
# GUI unusable. Leave two cores for the machine's owner.
set -euo pipefail

CONFIG="Debug-DMG"
while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIG="$2"; shift 2 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

cd "$(dirname "$0")/.."
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Jobhunt-local"
PRODUCT="$DERIVED_DATA/Build/Products/$CONFIG/JobhuntMigrator"

if [ ! -f "Jobhunt.xcodeproj/project.pbxproj" ]; then
    echo "→ Generating Xcode project (tuist generate)…"
    tuist generate --no-open
fi

echo "→ Building JobhuntMigrator ($CONFIG)…"
# The dedicated scheme — NOT `-target`, which reports success while emitting only a .swiftmodule.
xcodebuild build \
        -jobs 6 \
    -project Jobhunt.xcodeproj \
    -scheme JobhuntMigrator \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    | grep -E "error:|warning: .*JobhuntMigrator|BUILD (SUCCEEDED|FAILED)" || true

if [ ! -x "$PRODUCT" ]; then
    echo "✗ Build reported success but no executable at:" >&2
    echo "  $PRODUCT" >&2
    echo "  Do NOT run an older copy against the store — it may apply superseded logic." >&2
    exit 1
fi

echo
echo "✓ Built: $PRODUCT"
echo "  modified: $(stat -f '%Sm' "$PRODUCT")"
echo
echo "Run it with the Jobhunt app QUIT (the store is single-writer), e.g.:"
echo "  osascript -e 'quit app \"Jobhunt\"'"
echo "  \"$PRODUCT\" --help"
