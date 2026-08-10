#!/usr/bin/env bash
# Compiler-warning ratchet (TASK-570).
#
# A zero-warning gate isn't reachable today: the build carries ~49 distinct
# "KeyPath<Model, …> does not conform to Sendable" warnings emitted by SwiftData's own
# #Predicate/SortDescriptor machinery under strict concurrency. They're Apple's to fix, and
# suppressing them wholesale would also hide the handful of warnings that are ours.
#
# So this ratchets instead: count distinct warnings and fail if the count grows past the committed
# baseline. New warnings can't accrue, and lowering the baseline is a visible, deliberate commit.
#
#   ./scripts/check-warnings.sh            # build and compare against the baseline
#   ./scripts/check-warnings.sh --update   # rebuild and write the current count as the new baseline
set -euo pipefail

cd "$(dirname "$0")/.."
BASELINE_FILE=".warning-baseline"
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

# Clean build: an incremental one only recompiles changed files, so it would under-count and let a
# warning slip in on a file that happened to be cached.
warnings=$(
    xcodebuild clean build \
        -project Jobhunt.xcodeproj \
        -scheme Jobhunt-DMG \
        -configuration Debug-DMG \
        -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO 2>&1 |
        grep -E '^/.*warning:' | sort -u | wc -l | tr -d ' '
)

if [[ "${1:-}" == "--update" ]]; then
    echo "$warnings" >"$BASELINE_FILE"
    echo "Baseline updated to $warnings warnings."
    exit 0
fi

baseline=$(tr -d '[:space:]' <"$BASELINE_FILE")
echo "Distinct compiler warnings: $warnings (baseline $baseline)"

if ((warnings > baseline)); then
    cat <<EOF
FAIL: $((warnings - baseline)) new compiler warning(s).

Fix them, or — if they're genuinely unavoidable (a new SwiftData KeyPath case, say) — raise the
baseline deliberately with ./scripts/check-warnings.sh --update and say why in the commit message.
EOF
    exit 1
fi

if ((warnings < baseline)); then
    echo "Warnings dropped below the baseline. Run --update to lock in the improvement."
fi
