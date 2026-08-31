#!/usr/bin/env bash
# Compiler-warning ratchet (TASK-570).
#
# A zero-warning gate isn't reachable today: the build carries 14 warnings that are Apple's to
# fix — 13 "KeyPath<Model, …> does not conform to Sendable" from SwiftData's own
# #Predicate/SortDescriptor machinery under strict concurrency, plus NSEvent's unavailable
# Sendable conformance — and suppressing them wholesale would also hide the ones that are ours.
# (An earlier version of this comment claimed ~49 KeyPath warnings dominate the count. They
# don't: most are emitted against @__swiftmacro_… pseudo-paths, which the ^/.*warning: grep
# below never matches. Only 13 survive the filter.)
#
# So this ratchets instead: count distinct warnings and fail if the count grows past the committed
# baseline. New warnings can't accrue, and lowering the baseline is a visible, deliberate commit.
#
#   ./scripts/check-warnings.sh            # build and compare against the baseline
#   ./scripts/check-warnings.sh --update   # rebuild and write the current count as the new baseline
#
# The count is toolchain-dependent, so ALWAYS --update from a local build, never from CI's number.
# A newer Swift frontend emits diagnostics an older one doesn't. On 2026-08-31, identical source
# measured:
#
#   69   locally, Xcode 27.0 beta (27A5218g) / Swift 6.4
#   65   on CI, macos-latest's release Xcode 26.x
#
# and CI's 65 were a strict subset of the local 69 (the four extras: two Combine-import warnings in
# DashboardView, a `sending 'group'` in QueueActor, a weak/strong capture mismatch in JobhuntServer).
# The baseline is deliberately calibrated to the LOCAL, higher toolchain. Calibrating to CI's lower
# number would leave this script permanently red for everyone on the beta toolchain — the same
# "check nobody reads" failure the baseline itself exists to prevent.
#
# The accepted cost of that choice: because the baseline is ~4 above what CI counts, CI could absorb
# up to that many new warnings without failing. Local runs still catch them. When the toolchains
# converge, re-measure and --update to close the gap.
#
# It is also only stable per-tree: two worktrees sharing one DerivedData, or a second build running
# alongside, will disagree (see a8917a12). Measure from one checkout with nothing else building.
# -jobs 6 throughout: fanless 8-core MacBook Air. An uncapped build saturates every core,
# thermally throttles within minutes, and finishes slower than a capped one while making the
# GUI unusable. Leave two cores for the machine's owner.
set -euo pipefail

cd "$(dirname "$0")/.."
BASELINE_FILE=".warning-baseline"
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

# Clean build: an incremental one only recompiles changed files, so it would under-count and let a
# warning slip in on a file that happened to be cached.
warnings=$(
    xcodebuild clean build \
        -jobs 6 \
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
