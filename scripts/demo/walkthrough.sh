#!/usr/bin/env bash
# Drive the newcomer walkthrough: a real posting -> one-click capture -> the job arriving, being
# extracted and scored -> the per-requirement breakdown.
#
# Run reset.sh then configure.sh first. SCENE_LOG stamps each scene so caption timings come from
# measurement rather than from reading this file.
#
#   ./reset.sh && ./configure.sh OpenRouter mistralai/ministral-14b-2512
#   { ( sleep 1.5; SCENE_LOG=/tmp/scenes.txt ./walkthrough.sh ) & } \
#     && screencapture -v -V 120 -R 55,100,1600,900 /tmp/master.mov
#   ./cut.sh /tmp/master.mov marketing/demo
set -uo pipefail
L="${SCENE_LOG:-/dev/null}"; T0=$(python3 -c 'import time;print(time.time())')
s(){ python3 -c "import time;print(f'{time.time()-$T0:.2f}\t$1')" >> "$L"; }
app(){ osascript -e 'tell application "Jobhunt" to activate' >/dev/null 2>&1; }

# Assert, don't hope. Activating Chrome and trusting it is how two takes got recorded with no
# browser on screen: `activate` can no-op (wrong Space, window moved, Chrome not running) and the
# error was being swallowed by `2>/dev/null`. A take that can't show the capture is worthless, so
# fail here rather than spend two minutes recording it.
require_front() {
  local want="$1" got
  got=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1)
  if [ "$got" != "$want" ]; then
    echo "walkthrough: expected '$want' frontmost, got '$got' — aborting" >&2
    exit 1
  fi
}

s 01-posting
osascript -e 'tell application "Google Chrome" to activate' 2>&1
sleep 2
require_front "Google Chrome"
sleep 2
s 02-capture
osascript -e 'tell application "System Events" to keystroke "y" using {control down, shift down}' >/dev/null 2>&1
sleep 5                        # green OK badge appears on the extension button
s 03-app-receives
app; sleep 5                   # row arrives at the top of the list, still bare
s 04-processing
sleep 80                       # real extraction + scoring — cut out in post
s 05-filled-in
app
osascript <<'EOF' >/dev/null 2>&1
tell application "System Events" to tell process "Jobhunt"
  set sa to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
  set ol to outline 1 of sa
  repeat with r in rows of ol
    set lbl to ""
    try
      repeat with x in (static texts of (UI element 1 of r))
        set lbl to lbl & (value of x) & " "
      end repeat
    end try
    if lbl contains "Developer Productivity" then
      set selected of r to true
      exit repeat
    end if
  end repeat
end tell
EOF
sleep 6                        # detail pane: title, company, remote, salary
s 06-fit
osascript -e 'tell application "System Events" to tell process "Jobhunt" to click radio button 2 of radio group 1 of group 3 of splitter group 1 of group 1 of window 1' >/dev/null 2>&1
sleep 7                        # per-requirement breakdown
s 07-sort
# Rank the whole list by fit. The sort control is toolbar UI ELEMENT 5 — not `group 5`, which in
# AppleScript means "the 5th element of class group" and silently resolves to a different control (or
# to nothing: there are only four groups). The toolbar's order is defined in code rather than by data,
# so the index is stable in the way a list row's position is not.
# Escape on no match, or a stranded open menu ends up in the footage.
osascript <<'EOF' >/dev/null 2>&1
tell application "System Events" to tell process "Jobhunt"
  set mb to menu button 1 of (UI element 5 of toolbar 1 of window 1)
  click mb
  delay 1.2
  set picked to false
  try
    repeat with i from 1 to (count of menu items of menu 1 of mb)
      set mi to menu item i of menu 1 of mb
      if (name of mi) contains "Fit" then
        click mi
        set picked to true
        exit repeat
      end if
    end repeat
  end try
  if not picked then key code 53
end tell
EOF
sleep 7                        # the list reorders, best matches to the top
s end
