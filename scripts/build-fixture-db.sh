#!/usr/bin/env bash
# build-fixture-db.sh
#
# Regenerates tests/fixtures/jobhunt-test.sqlite from FixtureSeeder.
#
# Re-run this script whenever FixtureSeeder.swift changes so that the committed
# fixture stays in sync with the seeder.
#
# USAGE:
#   ./scripts/build-fixture-db.sh [--rebuild]
#
# FLAGS:
#   --rebuild    Run `tuist generate --no-open` before building (required after
#                any Project.swift change or after a clean checkout)
#
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

SCHEME="Jobhunt-DMG"
CONFIG="Debug-DMG"
PROJECT="Jobhunt.xcodeproj"
APP_NAME="Jobhunt"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Jobhunt-local"

REBUILD=false

# ── Argument parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild) REBUILD=true; shift ;;
        *) echo "Usage: $0 [--rebuild]" >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FIXTURE_PATH="$REPO_ROOT/tests/fixtures/jobhunt-test.sqlite"

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "  $*"; }
step() { echo; echo "▶ $*"; }
fail() { echo "✗ $*" >&2; exit 1; }

# ── Optional: regenerate Xcode project ───────────────────────────────────────

if [ "$REBUILD" = true ]; then
    step "Regenerating Xcode project"
    command -v tuist >/dev/null 2>&1 || fail "tuist not found. Install: mise install tuist or brew install tuist"
    nice tuist generate --no-open
    log "tuist generate complete"
fi

# ── Preflight ────────────────────────────────────────────────────────────────

step "Preflight"

[ -d "$PROJECT" ] || fail "$PROJECT not found. Run with --rebuild or run: tuist generate --no-open"
log "project: $REPO_ROOT/$PROJECT"
log "scheme:  $SCHEME"
log "output:  $FIXTURE_PATH"

# ── Build ─────────────────────────────────────────────────────────────────────

step "Building Jobhunt app"

nice xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    | xcbeautify 2>/dev/null \
    || nice xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_IDENTITY="" \
        CODE_SIGN_ENTITLEMENTS=""

log "build complete"

# ── Find built app ────────────────────────────────────────────────────────────

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIG/$APP_NAME.app"
APP_BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"

[ -f "$APP_BINARY" ] || fail "Built binary not found at $APP_BINARY"
log "binary:  $APP_BINARY"

# ── Seed fixture database ─────────────────────────────────────────────────────

step "Seeding fixture database"

# Remove stale fixture so we always start fresh
rm -f "$FIXTURE_PATH" \
      "$FIXTURE_PATH-shm" \
      "$FIXTURE_PATH-wal"

log "output: tests/fixtures/jobhunt-test.sqlite"

# Run synchronously — the app exits with code 0 after seeding completes.
# JobhuntApp.swift calls exit(0) at the end of FixtureSeeder.seed when
# --seed-fixture-output is present.
"$APP_BINARY" \
    --seed-fixture-output "$FIXTURE_PATH"

# ── Verify ────────────────────────────────────────────────────────────────────

[ -f "$FIXTURE_PATH" ] || fail "Fixture file not created at $FIXTURE_PATH"

# TASK-422: the committed fixture must be self-contained — readable without -wal/-shm sidecars.
# A non-empty WAL/SHM means recent writes live there and a copy of only the main file would be
# stale/incomplete. Fail loudly; otherwise drop empty sidecars so only the main file is committed.
for sidecar in "-wal" "-shm"; do
    sc="$FIXTURE_PATH$sidecar"
    if [ -s "$sc" ]; then
        fail "Non-empty sidecar $sc remains — fixture is not self-contained (data may be in the WAL)."
    fi
    rm -f "$sc"
done

SIZE_BYTES=$(wc -c < "$FIXTURE_PATH" | tr -d ' ')
if command -v python3 >/dev/null 2>&1; then
    SIZE_HUMAN=$(python3 -c "
s=$SIZE_BYTES
if s >= 1048576: print(f'{s/1048576:.1f} MB')
elif s >= 1024: print(f'{s/1024:.1f} KB')
else: print(f'{s} B')
")
else
    SIZE_HUMAN="${SIZE_BYTES} bytes"
fi

log "size: $SIZE_HUMAN"

# TASK-422: validate the generated fixture by reopening a fresh copy through the app's SwiftData
# config and checking expected counts (CoreTests/FixtureTests is the drift detector). Fails the
# build if the fixture is unreadable or its contents drifted from FixtureSeeder expectations.
step "Validating fixture (CoreTests/FixtureTests)"
nice xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -only-testing:CoreTests/FixtureTests \
    CODE_SIGNING_ALLOWED=NO \
    || fail "Fixture validation failed — counts drifted or the fixture is unreadable. If FixtureSeeder changed intentionally, update CoreTests/FixtureTests expectations."
log "fixture validated"

step "Done — commit tests/fixtures/jobhunt-test.sqlite to git"
