#!/usr/bin/env bash
# Dead-code ratchet (TASK-570).
#
# Same shape as check-warnings.sh, and for the same reason: the scan reports 47 findings today, so a
# zero-findings gate would have to be either a large deletion commit bolted onto whatever change
# tripped it, or switched off. Instead the count is committed, growth fails, and working the number
# down (TASK-690) is a deliberate commit.
#
# The noisy analyses are disabled in .periphery.yml, with the reasoning there — this counts what's
# left, which is genuine unused types, functions and properties.
#
#   ./scripts/check-periphery.sh            # scan and compare against the baseline
#   ./scripts/check-periphery.sh --update   # rescan and write the current count as the new baseline
#   ./scripts/check-periphery.sh --list     # scan and print the findings
set -euo pipefail

cd "$(dirname "$0")/.."
BASELINE_FILE=".periphery-baseline"

if ! command -v periphery >/dev/null 2>&1; then
    echo "periphery not found. brew install peripheryapp/periphery/periphery" >&2
    exit 1
fi

# Periphery drives its own xcodebuild, so the project has to exist first. -jobs isn't exposed; the
# nice is what keeps the machine usable.
[ -d Jobhunt.xcodeproj ] || tuist generate --no-open

findings="$(nice periphery scan 2>/dev/null | grep -E '^/.*warning:' || true)"
count=$(printf '%s' "$findings" | grep -c . || true)

if [[ "${1:-}" == "--list" ]]; then
    printf '%s\n' "$findings"
    echo "---"
fi

if [[ "${1:-}" == "--update" ]]; then
    echo "$count" >"$BASELINE_FILE"
    echo "Baseline updated to $count findings."
    exit 0
fi

baseline=$(tr -d '[:space:]' <"$BASELINE_FILE")
echo "Unused declarations: $count (baseline $baseline)"

if ((count > baseline)); then
    printf '%s\n' "$findings"
    cat <<EOF

FAIL: $((count - baseline)) new unused declaration(s).

Delete the dead code, or — if Periphery is wrong about it (something reached only through a
selector, a KVO key path, or SwiftUI's own machinery) — retain it explicitly in .periphery.yml and
say why. Raising the baseline is the last resort, not the first.
EOF
    exit 1
fi

if ((count < baseline)); then
    echo "Findings dropped below the baseline. Run --update to lock in the improvement."
fi
