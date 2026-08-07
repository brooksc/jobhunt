#!/usr/bin/env bash
# Put the app into a known state for a demo recording.
#
# `--ui-test-store` opens an isolated temp store that ModelContainerFactory.freshTestStore() DELETES
# on every launch, so relaunching is a complete reset — the demo data is re-seeded and any scoring
# correction made during a previous take is gone. The user's real store is never touched.
set -euo pipefail

APP="${JOBHUNT_APP:-$HOME/Library/Developer/Xcode/DerivedData/Jobhunt-local/Build/Products/Debug-DMG/Jobhunt.app}"
X=${CAPTURE_X:-55}
Y=${CAPTURE_Y:-100}
W=${CAPTURE_W:-1600}
H=${CAPTURE_H:-900}

[ -d "$APP" ] || { echo "No app at $APP — build Debug-DMG first." >&2; exit 1; }

pkill -f "Jobhunt.app/Contents/MacOS/Jobhunt" 2>/dev/null || true
sleep 1.5
# --run-queue: the isolated store otherwise starts the queue paused (that default exists for
# UI tests, which assert on seeded .pending rows). A demo needs the pipeline to actually run.
open -n "$APP" --args --ui-test-store --seed-demo-data --run-queue
sleep 7

# Size in POINTS. screencapture records the region at 2x on Retina, so 1600x900 -> 3200x1800, which
# is exactly 16:9 and scales to 1920x1080 with no crop and no letterboxing.
osascript <<EOF
tell application "System Events" to tell process "Jobhunt"
  set frontmost to true
  delay 0.5
  set position of window 1 to {$X, $Y}
  set size of window 1 to {$W, $H}
  delay 0.3
  return (position of window 1) & (size of window 1)
end tell
EOF

# Stage the browser too. The walkthrough opens on a real posting, and NOTHING here used to guarantee
# one was on screen: the driver just activated whatever Chrome happened to be, with stderr
# suppressed. Two takes recorded with no browser in frame at all — the first three captions narrating
# a capture the viewer never sees — and both passed the scene-log check, because the log records that
# the script reached a line, not that anything appeared.
POSTING="${DEMO_POSTING_URL:-https://job-boards.greenhouse.io/reddit/jobs/7944159}"
osascript <<EOF
tell application "Google Chrome"
  activate
  if (count of windows) is 0 then
    make new window
  end if
  set URL of active tab of front window to "$POSTING"
  -- Same rect as the app window: whichever is frontmost has to fill the capture region exactly.
  set bounds of front window to {$X, $Y, $X + $W, $Y + $H}
end tell
EOF
sleep 4
