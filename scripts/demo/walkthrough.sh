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

s 01-posting
osascript -e 'tell application "Google Chrome" to activate' >/dev/null 2>&1; sleep 4
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
  set ol to outline 1 of scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
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
sleep 7                        # detail pane: title, company, remote, salary
s 06-fit
osascript -e 'tell application "System Events" to tell process "Jobhunt" to click radio button 2 of radio group 1 of group 3 of splitter group 1 of group 1 of window 1' >/dev/null 2>&1
sleep 9                        # per-requirement breakdown
s end
