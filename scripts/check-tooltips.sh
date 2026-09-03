#!/usr/bin/env bash
# Icon-only controls must carry an accessibility label (TASK-494, corrected by TASK-700).
#
# An audit fixes today's gaps; this stops tomorrow's. A button whose entire label is an SF Symbol
# tells VoiceOver nothing, and they reappear steadily because an icon-only button is the quickest
# thing to write.
#
# **`.help()` is NOT a label.** SwiftUI's `.help()` sets the accessibility *hint*; the control still
# has no *name*, so VoiceOver announces "button" and the tooltip arrives as detail about a control
# the user cannot identify. This check accepted either token until TASK-700, and its failure message
# told developers to add `.help()` — which is how ~120 `.help(` accumulated against ~28
# `.accessibilityLabel(`. A guard enforcing the wrong invariant is worse than no guard.
#
# Heuristic, deliberately: it looks for a `Button` whose following lines contain an
# `Image(systemName:)` with no `Text(`, `Label(` or `.accessibilityLabel(` nearby.
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
        # fine (six such false positives on the first run). Finding the label needs a LONGER one,
        # because `.accessibilityLabel()` sits after the label closure, past where the Image was.
        label_block = "\n".join(lines[i:i + 8])
        modifier_block = "\n".join(lines[i:i + 18])
        if "Image(systemName:" not in label_block:
            continue
        if any(token in label_block for token in ("Text(", "Label(")):
            continue
        if ".accessibilityLabel(" in modifier_block:
            continue
        offenders.append(f"{path}:{i + 1}: {line.strip()[:70]}")

if offenders:
    print("Icon-only controls with no .accessibilityLabel():\n")
    print("\n".join(offenders))
    print(
        f"\n{len(offenders)} offender(s). Add .accessibilityLabel(\"…\") naming the SPECIFIC target,\n"
        "e.g. .accessibilityLabel(\"Remove \\(source.label)\") — in a column of identical trash icons a\n"
        "generic \"Remove\" is nearly as useless as none. .help() is a hint, not a name: it does NOT\n"
        "satisfy this check, and is worth keeping only where it adds detail beyond the label."
    )
    sys.exit(1)

print("No icon-only controls missing an accessibility label.")
PY
