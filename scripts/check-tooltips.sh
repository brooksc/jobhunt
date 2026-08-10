#!/usr/bin/env bash
# Icon-only controls must carry a tooltip (TASK-494).
#
# An audit fixes today's gaps; this stops tomorrow's. A button whose entire label is an SF Symbol
# tells the user nothing on hover and nothing to VoiceOver, and they reappear steadily because an
# icon-only button is the quickest thing to write.
#
# Heuristic, deliberately: it looks for a `Button` whose following lines contain an
# `Image(systemName:)` with no `Text(`, `Label(`, `.help(` or `.accessibilityLabel(` nearby. It can
# be fooled, so it reports rather than fails by default.
#
#   ./scripts/check-tooltips.sh          # list offenders, exit 1 if any
set -euo pipefail
cd "$(dirname "$0")/.."

nice python3 - <<'PY'
import pathlib, re, sys

offenders = []
for path in sorted(pathlib.Path("app").rglob("*.swift")):
    lines = path.read_text().split("\n")
    for i, line in enumerate(lines):
        # Only trailing-closure/action-only buttons: `Button("3 days") { … }` already has a title,
        # and so does `Button(someLabelString)`.
        if not re.match(r"\s*Button\s*(\{|\(action:)", line):
            continue
        # Two window sizes, and the difference matters. Detecting "is this icon-only" needs a SHORT
        # window: wider, and it picks up an Image from the next view and reports a button that was
        # fine (six such false positives on the first run). Finding the tooltip needs a LONGER one,
        # because `.help()` sits after the label closure, past where the Image was (two more).
        label_block = "\n".join(lines[i:i + 8])
        modifier_block = "\n".join(lines[i:i + 18])
        if "Image(systemName:" not in label_block:
            continue
        if any(token in label_block for token in ("Text(", "Label(")):
            continue
        if any(token in modifier_block for token in (".help(", ".accessibilityLabel(")):
            continue
        offenders.append(f"{path}:{i + 1}: {line.strip()[:70]}")

if offenders:
    print("Icon-only controls with no .help() tooltip:\n")
    print("\n".join(offenders))
    print(f"\n{len(offenders)} offender(s). Add .help(\"…\") describing the action.")
    sys.exit(1)

print("No icon-only controls missing a tooltip.")
PY
