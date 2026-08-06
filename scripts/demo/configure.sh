#!/usr/bin/env bash
# Point the demo instance at a real cloud model, so a captured job actually extracts and scores.
#
#   ./configure.sh [provider] [model]
#   ./configure.sh OpenRouter deepseek/deepseek-v4-flash        (defaults)
#
# Run AFTER reset.sh: `--ui-test-store` deletes the store on every launch, taking the provider,
# the consent and the model with it.
#
# The API key is NOT set here and never appears in this script — it is read from the login Keychain,
# which the demo instance shares with the normal build because the bundle ID is the same. If no key
# is present for the chosen provider, configure it once in the real app and it will be found here.
set -euo pipefail

PROVIDER="${1:-OpenRouter}"
MODEL="${2:-deepseek/deepseek-v4-flash}"

osascript <<EOF
-- Activate through the app, not System Events' \`set frontmost\`: the latter silently fails often
-- enough that the very next keystroke goes to whatever was previously frontmost.
tell application "Jobhunt" to activate
delay 1.5
tell application "System Events" to tell process "Jobhunt"
  keystroke "," using command down
  delay 2.5
  -- Toolbar item 3 is the AI tab. The tabs carry no accessible name, but their order is defined in
  -- code rather than by data, so the index is stable.
  click UI element 3 of toolbar 1 of window 1
  -- Poll for the tab switch: the settings window is renamed after the click, and referencing
  -- window "AI" too early fails with -1728.
  repeat 20 times
    try
      if (name of window 1) is "AI" then exit repeat
    end try
    delay 0.5
  end repeat
  delay 0.5

  -- Park the settings window inside the capture region; where it opens depends on display layout.
  repeat with i from 1 to (count of windows)
    if (name of window i) is not "All Jobs" then set position of window i to {430, 260}
  end repeat
  delay 0.5

  set g to group 1 of scroll area 1 of group 1 of window "AI"

  -- Provider. Address menu items BY NAME — the picker is fully scriptable this way. Do not try to
  -- drive these menus with keystrokes: they ignore type-select entirely (TASK-665).
  click pop up button "Provider" of g
  delay 0.8
  click menu item "$PROVIDER" of menu 1 of pop up button "Provider" of g
  delay 2

  -- Cloud providers ask for consent before any job text is sent. Accept it; the sheet's buttons
  -- carry no names, so take the right-most, which is the default action.
  -- POLL for the sheet. Checking once misses it when the sheet is slow to appear, and the cost of
  -- missing it is silent and total: without consent AIReadiness.isConfigured() is false, so the drain
  -- loop exits immediately and every captured job sits queued forever with no error shown.
  repeat 20 times
    if (count of sheets of window "AI") > 0 then exit repeat
    delay 0.5
  end repeat
  if (count of sheets of window "AI") > 0 then
    set sh to group 1 of sheet 1 of window "AI"
    set bestX to -1
    set bestI to 0
    repeat with i from 1 to (count of buttons of sh)
      set pt to value of attribute "AXPosition" of button i of sh
      if (item 1 of pt) > bestX then
        set bestX to (item 1 of pt)
        set bestI to i
      end if
    end repeat
    click button bestI of sh
    delay 2
  end if

  -- Fetch the model list, then pick the model by name.
  repeat with i from 1 to (count of buttons of g)
    try
      if (description of button i of g) contains "Fetch" then click button i of g
    end try
  end repeat
  delay 8

  click pop up button "Model" of g
  delay 1
  click menu item "$MODEL" of menu 1 of pop up button "Model" of g
  delay 1.5

  set chosen to value of pop up button "Model" of g
  set chosenProvider to value of pop up button "Provider" of g

  -- Close settings so the main window is the only thing on screen. Iterate by index DOWNWARDS:
  -- the window collection shrinks as each one closes, so a forward loop runs off the end.
  repeat with i from (count of windows) to 1 by -1
    if (name of window i) is not "All Jobs" then click button 1 of window i
  end repeat

  return chosenProvider & " / " & chosen
end tell
EOF
