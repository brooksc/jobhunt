#!/usr/bin/env bash
# run-eval.sh — run the LLM extraction benchmark (tests/LLMEval) against an
# OpenAI-compatible endpoint (e.g. LM Studio). Exercises the real
# ExtractionEngine.extract path used at runtime and prints an accuracy report.
#
# Usage:
#   scripts/run-eval.sh <model-id> [min-accuracy-percent]
#
# Examples:
#   scripts/run-eval.sh gemma-4-e2b-it-mlx            # reporting mode (never fails)
#   scripts/run-eval.sh gemma-4-e2b-it-mlx 80         # fail below 80%
#
# Env overrides:
#   JOBHUNT_LLM_URL   base URL of the endpoint (default http://127.0.0.1:1234)
#   JOBHUNT_LLM_MODEL model id (alternative to the positional arg)
set -euo pipefail

cd "$(dirname "$0")/.."

MODEL="${1:-${JOBHUNT_LLM_MODEL:-}}"
MIN="${2:-${JOBHUNT_LLM_MIN_ACCURACY:-}}"
URL="${JOBHUNT_LLM_URL:-http://127.0.0.1:1234}"

if [ -z "$MODEL" ]; then
    echo "usage: scripts/run-eval.sh <model-id> [min-accuracy-percent]" >&2
    echo "  e.g. scripts/run-eval.sh gemma-4-e2b-it-mlx" >&2
    exit 1
fi

# Generate the Xcode project if it isn't present (the Jobhunt-Eval scheme lives there).
[ -d Jobhunt.xcodeproj ] || tuist generate --no-open

# xcodebuild does not forward the invoking shell's environment to the XCTest process, so the
# harness reads its config from ~/.jobhunt-lmstudio-* files. Write them here.
printf '%s' "$URL" > "$HOME/.jobhunt-lmstudio-url"
printf '%s' "$MODEL" > "$HOME/.jobhunt-lmstudio-model"
if [ -n "$MIN" ]; then
    printf '%s' "$MIN" > "$HOME/.jobhunt-lmstudio-min-accuracy"
else
    rm -f "$HOME/.jobhunt-lmstudio-min-accuracy" # default to reporting mode
fi

echo "Running LLM eval — URL=$URL  MODEL=$MODEL  MIN_ACCURACY=${MIN:-none}"
echo

nice xcodebuild test \
    -project Jobhunt.xcodeproj \
    -scheme Jobhunt-Eval \
    -configuration Debug-DMG \
    -destination 'platform=macOS' \
    -only-testing:LLMEval \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | grep -E '=== |\[PASS\]|\[FAIL\]|Score:|Model:|Overall|Provider URL:|skipped|XCTSkip|below threshold|error:|TEST (SUCCEEDED|FAILED)' || true
