#!/usr/bin/env bash
# Drive the demo walkthrough via the accessibility API.
#
# Run reset.sh first. Set SCENE_LOG to a path and each scene stamps its start offset in seconds —
# caption timings are derived from that log, never guessed from the script, because AppleScript step
# durations drift between runs.
#
# DRY_RUN=1 runs the whole thing and asserts state without a recording attached.
set -uo pipefail

SCENE_LOG="${SCENE_LOG:-/dev/null}"
START=$(python3 -c 'import time; print(time.time())')
: > "$SCENE_LOG"

scene() { # scene <name>
  python3 -c "import time; print(f'{time.time()-$START:.2f}\t$1')" >> "$SCENE_LOG"
}

fail() { echo "ASSERT FAILED: $*" >&2; exit 1; }

# Every block re-activates the app: a stray focus change sends keystrokes to whatever is frontmost.
# The delay after `set frontmost` is not padding — activation makes SwiftUI rebuild the pane, and for
# ~1s the buttons come back with no AXHelp, so a matcher run immediately after finds nothing.
osa() { osascript 2>&1; }

select_job() { # select_job <needle>
  osa <<EOF
tell application "System Events" to tell process "Jobhunt"
  set frontmost to true
  delay 0.6
  set ol to outline 1 of scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
  repeat with r in rows of ol
    set lbl to ""
    try
      repeat with s in (static texts of (UI element 1 of r))
        set lbl to lbl & (value of s) & " "
      end repeat
    end try
    -- Address rows by their text, never by index: any filter or status change reorders the list.
    if lbl contains "$1" then
      set selected of r to true
      delay 0.5
      return "ok"
    end if
  end repeat
  return "MISSING"
end tell
EOF
}

detail_tab() { # detail_tab <index>  (1=Overview 2=Fit 3=Timeline 4=Description 5=Raw)
  # The tabs expose neither name nor child text over AX, so index is the only handle. The order is
  # defined in code, not by data, so it can't shift the way list rows can.
  osa <<EOF
tell application "System Events" to tell process "Jobhunt"
  set frontmost to true
  delay 0.5
  click radio button $1 of radio group 1 of group 3 of splitter group 1 of group 1 of window 1
  delay 0.7
  return "ok"
end tell
EOF
}

fit_score_text() {
  osa <<'EOF'
tell application "System Events" to tell process "Jobhunt"
  set sa to scroll area 1 of group 3 of splitter group 1 of group 1 of window 1
  repeat with e in (UI elements of sa)
    try
      if role of e is "AXStaticText" then
        set v to value of e
        if v contains "Best match" then return v
      end if
    end try
  end repeat
  return "NONE"
end tell
EOF
}

# ---------------------------------------------------------------- scenes

scene "01-list"
sleep 2.5

scene "02-select-job"
[ "$(select_job Google)" = "ok" ] || fail "could not select the Google row"
sleep 2

scene "03-fit-tab"
detail_tab 2 >/dev/null
BEFORE=$(fit_score_text)
echo "$BEFORE" | grep -q "84" || fail "expected the Google job to start at 84, got: $BEFORE"
sleep 3.5

scene "04-flag-gap"
# The gap sits in the right-hand "Gaps" column, so its flag is the right-most one. Picking by
# max-x rather than by index survives a job having a different number of met rows.
CLICKED=$(osa <<'EOF'
tell application "System Events" to tell process "Jobhunt"
  set frontmost to true
  -- POLL, don't sleep-and-hope. After a tab switch the flag buttons exist for a moment with no
  -- AXHelp, so a single matcher pass behind a fixed delay finds nothing and the scene silently
  -- no-ops. This retries for up to ~10s.
  set bestI to 0
  set bestX to -1
  repeat 20 times
    set bestI to 0
    set bestX to -1
    -- Re-resolve the scroll area every pass: a reference captured before/around activation goes
    -- stale, every access then throws, the `try` swallows it, and the poll spins finding nothing.
    set sa to scroll area 1 of group 3 of splitter group 1 of group 1 of window 1
    -- Two AppleScript traps here, both of which fail SILENTLY inside the `try`:
    --  1. Index the elements. Iterating `UI elements of sa` yields loop REFERENCES, and geometry
    --     lookups on a reference raise -1700 ("can't make ... into type specifier").
    --  2. Read geometry as `value of attribute "AXPosition"`, never `position of`, AND assign it to
    --     a variable before subscripting. `item 1 of (value of attribute ... of x)` parses into
    --     something System Events rejects; the two-step form works. Both failures land in the `try`,
    --     so the scan matches every flag and then silently discards all of them.
    repeat with i from 1 to (count of UI elements of sa)
      try
        if role of (UI element i of sa) is "AXButton" then
          set h to help of (UI element i of sa)
          if h is not missing value and h contains "assessment is wrong" then
            set pt to value of attribute "AXPosition" of (UI element i of sa)
            set px to item 1 of pt
            if px > bestX then
              set bestX to px
              set bestI to i
            end if
          end if
        end if
      end try
    end repeat
    if bestI > 0 then exit repeat
    delay 0.5
  end repeat
  if bestI = 0 then return "MISSING"
  click UI element bestI of sa
  delay 1.5
  if (count of sheets of window 1) = 0 then return "NOSHEET"
  return "ok"
end tell
EOF
)
[ "$CLICKED" = "ok" ] || fail "gap flag did not open the correction sheet ($CLICKED)"
sleep 2.5

scene "05-save-correction"
# Sheet buttons expose no name; Save is the right-most. Note the positional lookup must index
# (`button i of g`) — iterating `buttons of g` as references makes `position of` unresolvable.
SAVED=$(osa <<'EOF'
tell application "System Events" to tell process "Jobhunt"
  set frontmost to true
  delay 0.8
  set g to group 1 of sheet 1 of window 1
  set bestX to -1
  set bestI to 0
  repeat with i from 1 to (count of buttons of g)
    set pt to value of attribute "AXPosition" of button i of g
    set px to item 1 of pt
    if px > bestX then
      set bestX to px
      set bestI to i
    end if
  end repeat
  click button bestI of g
  delay 2
  if (count of sheets of window 1) > 0 then return "STILLOPEN"
  return "ok"
end tell
EOF
)
[ "$SAVED" = "ok" ] || fail "correction sheet did not close ($SAVED)"
sleep 2

scene "06-rescored"
# The headline score does NOT refresh in place after a correction (the requirement row moves to
# "met" but the ring keeps its old value) — reselecting rebuilds it. Filmed as-is rather than
# faked; see the README.
select_job Stripe >/dev/null
[ "$(select_job Google)" = "ok" ] || fail "could not reselect Google"
detail_tab 2 >/dev/null
AFTER=$(fit_score_text)
echo "$AFTER" | grep -q "94" || fail "expected 94 after the correction, got: $AFTER"
sleep 3.5


scene "07-local-model"
osa <<'EOF' >/dev/null
tell application "System Events" to tell process "Jobhunt"
  set frontmost to true
  delay 0.8
  keystroke "," using command down
  delay 1.5
  click UI element 3 of toolbar 1 of window 1
  delay 1
end tell
EOF
sleep 2.5

scene "end"
echo "all scenes fired; 84 -> 94 confirmed"
