#!/usr/bin/env bash
# check-coverage.sh — enforce a line-coverage floor for the unit-test frameworks.
#
# Computes combined line coverage for JobhuntCore + JobhuntServer from an
# .xcresult bundle and fails if it drops below the floor. This is a ratchet:
# raise MIN_LINE_COVERAGE as coverage improves; never let it regress.
#
# Note: xccov reports LINE coverage only (no branch coverage), so this gate is
# line-based. The legacy Node project's 85/78 line/branch gate does not apply
# to the Swift codebase.
#
# Usage: scripts/check-coverage.sh <result.xcresult> [min_line_percent]
set -euo pipefail

RESULT="${1:?usage: check-coverage.sh <result.xcresult> [min_line_percent]}"
MIN="${2:-${MIN_LINE_COVERAGE:-68}}"
TARGETS="JobhuntCore.framework JobhuntServer.framework"

[ -e "$RESULT" ] || { echo "✗ result bundle not found: $RESULT" >&2; exit 1; }

xcrun xccov view --report --json "$RESULT" 2>/dev/null | MIN="$MIN" TARGETS="$TARGETS" python3 -c '
import json, os, sys
data = json.load(sys.stdin)
wanted = set(os.environ["TARGETS"].split())
tot = cov = 0
rows = []
for t in data.get("targets", []):
    if t["name"] in wanted:
        tot += t["executableLines"]; cov += t["coveredLines"]
        rows.append((t["name"], t["lineCoverage"] * 100, t["coveredLines"], t["executableLines"]))
if not tot:
    print("✗ no coverage data for", wanted, file=sys.stderr); sys.exit(1)
pct = cov / tot * 100
floor = float(os.environ["MIN"])
for name, p, c, e in rows:
    print(f"  {name}: {p:.2f}% ({c}/{e})")
print(f"  COMBINED: {pct:.2f}% ({cov}/{tot})  floor={floor:.0f}%")
if pct + 1e-9 < floor:
    print(f"✗ coverage {pct:.2f}% is below floor {floor:.0f}%", file=sys.stderr); sys.exit(1)
print(f"✓ coverage {pct:.2f}% meets floor {floor:.0f}%")
'
