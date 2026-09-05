#!/bin/sh
# check-stale-artifacts.sh (TASK-418)
#
# Lists git-IGNORED local release/build artifacts and flags ones that are STALE relative to the
# current source versions, so a release or store submission can't accidentally rely on an old DMG /
# extension zip / Derived output left in the working tree.
#
# Ignored artifacts are NEVER authoritative on their own — regenerate them with the current scripts
# (scripts/package-extension.sh, the release workflow) before using them. This is a read-only report;
# it deletes nothing.
#
# Usage: ./scripts/check-stale-artifacts.sh
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

EXT_VERSION=$(node -e "console.log(require('./extension/manifest.json').version)" 2>/dev/null || echo "?")
stale=0

say()  { printf '%s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; stale=1; }

say "Current source versions:"
say "  extension/manifest.json: $EXT_VERSION"
say ""

# ── Chrome extension zips ─────────────────────────────────────────────────────
say "Chrome extension zips (chromestore/):"
found_ext=0
for zip in chromestore/jobhunt-capture-*.zip; do
    [ -e "$zip" ] || continue
    found_ext=1
    zver=$(basename "$zip" | sed -E 's/jobhunt-capture-(.*)\.zip/\1/')
    if [ "$zver" = "$EXT_VERSION" ]; then
        say "  ✓ $zip (matches current manifest)"
    else
        warn "$zip is version $zver but manifest is $EXT_VERSION — stale; re-run scripts/package-extension.sh"
    fi
done
[ "$found_ext" -eq 1 ] || say "  (none)"
say ""

# ── DMGs ──────────────────────────────────────────────────────────────────────
say "DMGs (build/, repo root):"
found_dmg=0
for dmg in build/*.dmg ./*.dmg; do
    [ -e "$dmg" ] || continue
    found_dmg=1
    warn "$dmg ($(date -r "$dmg" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')) — verify it was built from the current commit"
done
[ "$found_dmg" -eq 1 ] || say "  (none)"
say ""

# ── Heavy build output ────────────────────────────────────────────────────────
say "Generated build output (ignored — safe to delete; regenerated on build):"
for d in Jobhunt.xcodeproj Jobhunt.xcworkspace build .build Derived; do
    [ -e "$d" ] && say "  • $d"
done

say ""
if [ "$stale" -eq 1 ]; then
    say "Stale artifacts found ⚠ — regenerate with the current scripts before releasing/submitting."
    exit 1
fi
say "No stale release artifacts detected."
