#!/usr/bin/env bash
# screenshot-views.sh — Navigate each Jobhunt view and capture a screenshot.
# Output: screenshots/<timestamp>/  (directory excluded from git)
#
# Strategy: AppleScript accessibility returns no label text for any sidebar button,
# so this script navigates by BUTTON INDEX (discovered via the click-test below)
# and clicks Jobs view filter pills by x/y coordinate.
#
# Sidebar button map (10 buttons, collapsed Jobs section):
#   1=Dashboard  2=Jobs(all)  3=Needs Action  4=Sites  5=Duplicates
#   6-8=Saved Searches  9=LLM Queue  10=Data Quality
#
# Jobs filter pills (at y≈138 in Jobs view):
#   All  Saved  Applied  Interview  Offer  Rejected

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TS="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="$REPO_ROOT/screenshots/$TS"
mkdir -p "$OUT_DIR"

APP_NAME="Jobhunt"

log() { echo "▸ $*"; }

# ── ensure app is running ─────────────────────────────────────────────────────

if ! pgrep -x "$APP_NAME" > /dev/null; then
    log "Launching $APP_NAME…"
    APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" \
        -path '*/Debug-DMG/*' -not -path '*/PlugIns/*' 2>/dev/null | head -1)"
    if [[ -z "$APP_PATH" ]]; then
        APP_PATH="$(find "$REPO_ROOT/build" -name "${APP_NAME}.app" \
            -not -path '*/PlugIns/*' 2>/dev/null | head -1)"
    fi
    if [[ -z "$APP_PATH" ]]; then
        echo "ERROR: Could not find ${APP_NAME}.app — build the app first." >&2
        exit 1
    fi
    open "$APP_PATH"
    sleep 3
fi

# Bring app to front and let it settle
osascript -e "tell application \"$APP_NAME\" to activate" 2>/dev/null || true
sleep 0.5

# ── helper: capture just the app window ──────────────────────────────────────

capture_window() {
    local outfile="$1"
    # Get the CGWindowID of the frontmost Jobhunt window
    local wid
    wid="$(python3 -c "
import Quartz
wins = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
for w in wins:
    if 'Jobhunt' in str(w.get('kCGWindowOwnerName','')) and w.get('kCGWindowLayer',0) == 0:
        print(w.get('kCGWindowNumber',0))
        break
" 2>/dev/null || echo "0")"

    if [[ "$wid" == "0" ]]; then
        screencapture -x "$outfile"   # fallback: full screen
    else
        screencapture -l "$wid" -x "$outfile"
    fi
}

# ── helper: click sidebar button by 1-based index, wait, screenshot ───────────

sidebar_screenshot() {
    local idx="$1"
    local label="$2"
    log "Sidebar btn $idx → $label"
    osascript <<SCRIPT
tell application "System Events"
    tell process "$APP_NAME"
        set frontmost to true
        delay 0.2
        click button $idx of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
        delay 1.0
    end tell
end tell
SCRIPT
    capture_window "$OUT_DIR/${label}.png"
    log "  → ${label}.png"
}

# ── helper: click Jobs filter pill by x-center coordinate, wait, screenshot ──

jobs_pill_screenshot() {
    local x_center="$1"
    local label="$2"
    log "Jobs filter pill x=$x_center → $label"
    osascript <<SCRIPT
tell application "System Events"
    tell process "$APP_NAME"
        set frontmost to true
        delay 0.1
        -- Find the pill button nearest to x=$x_center at y≈138
        set ec to entire contents of window 1
        set bestBtn to missing value
        set bestDist to 9999
        repeat with el in ec
            try
                if role of el is "AXButton" then
                    set p to position of el
                    set py to item 2 of p
                    set px to item 1 of p
                    set s to size of el
                    set pw to item 1 of s
                    if py > 130 and py < 155 and px > 200 then
                        -- center of button
                        set cx to px + (pw / 2)
                        set dist to (cx - $x_center) * (cx - $x_center)
                        if dist < bestDist then
                            set bestDist to dist
                            set bestBtn to el
                        end if
                    end if
                end if
            end try
        end repeat
        if bestBtn is not missing value then
            click bestBtn
        end if
        delay 1.0
    end tell
end tell
SCRIPT
    capture_window "$OUT_DIR/${label}.png"
    log "  → ${label}.png"
}

# ── helper: detect saved search names from sidebar text ──────────────────────

get_saved_search_labels() {
    # Read the sidebar SAVED SEARCHES section header to find actual search names
    # They appear as AXStaticText elements in the scroll area after "SAVED SEARCHES"
    osascript <<'AS' 2>/dev/null || true
tell application "System Events"
    tell process "Jobhunt"
        set sa to scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
        set allEls to UI elements of sa
        set inSavedSearches to false
        set names to {}
        repeat with el in allEls
            try
                if role of el is "AXStaticText" then
                    set v to value of el
                    if v is "SAVED SEARCHES" then
                        set inSavedSearches to true
                    else if inSavedSearches then
                        set inSavedSearches to false
                    end if
                end if
            end try
        end repeat
        -- fallback: click each saved-search button and read the window subtitle
        return ""
    end tell
end tell
AS
}

# ── main sequence ─────────────────────────────────────────────────────────────

log "Output: $OUT_DIR"
log ""

# 1. Dashboard
sidebar_screenshot 1 "01_Dashboard"

# 2. Jobs – All (section header navigates to all-jobs view)
sidebar_screenshot 2 "02_Jobs_All"

# 3. Jobs – Saved (click Saved filter pill; x center ≈ 282)
jobs_pill_screenshot 282 "03_Jobs_Saved"

# 4. Jobs – Applied (x center ≈ 340)
jobs_pill_screenshot 340 "04_Jobs_Applied"

# 5. Jobs – Interview (x center ≈ 406)
jobs_pill_screenshot 406 "05_Jobs_Interview"

# 6. Jobs – Offer (x center ≈ 466)
jobs_pill_screenshot 466 "06_Jobs_Offer"

# 7. Jobs – Rejected (x center ≈ 524)
jobs_pill_screenshot 524 "07_Jobs_Rejected"

# 8. Reset Jobs filter to All before moving on (x center ≈ 236)
log "Resetting Jobs filter to All…"
osascript <<'RESET'
tell application "System Events"
    tell process "Jobhunt"
        set ec to entire contents of window 1
        set bestBtn to missing value
        set bestDist to 9999
        repeat with el in ec
            try
                if role of el is "AXButton" then
                    set p to position of el
                    set py to item 2 of p
                    set px to item 1 of p
                    set s to size of el
                    set pw to item 1 of s
                    if py > 130 and py < 155 and px > 200 then
                        set cx to px + (pw / 2)
                        set dist to (cx - 236) * (cx - 236)
                        if dist < bestDist then
                            set bestDist to dist
                            set bestBtn to el
                        end if
                    end if
                end if
            end try
        end repeat
        if bestBtn is not missing value then click bestBtn
        delay 0.5
    end tell
end tell
RESET

# 9. Needs Action
sidebar_screenshot 3 "08_Needs_Action"

# 10. Sites
sidebar_screenshot 4 "09_Sites"

# 11. Duplicates
sidebar_screenshot 5 "10_Duplicates"

# 12. Saved Searches (click each, read window to get name)
for sidx in 6 7 8; do
    num=$((sidx - 5 + 10))
    label="$(printf '%02d_SavedSearch_%d' "$num" $((sidx - 5)))"
    sidebar_screenshot "$sidx" "$label"
done

# 13. LLM Queue
sidebar_screenshot 9 "14_LLM_Queue"

# 14. Data Quality
sidebar_screenshot 10 "15_Data_Quality"

# ── verify all screenshots differ ─────────────────────────────────────────────

log ""
log "Verifying screenshots are distinct…"
cd "$OUT_DIR"
dupes=0
files=( *.png )
for ((i=0; i<${#files[@]}; i++)); do
    for ((j=i+1; j<${#files[@]}; j++)); do
        if diff -q "${files[$i]}" "${files[$j]}" > /dev/null 2>&1; then
            log "  WARNING: ${files[$i]} == ${files[$j]} (identical!)"
            dupes=$((dupes + 1))
        fi
    done
done
if [[ "$dupes" -eq 0 ]]; then
    log "  All $(ls *.png | wc -l | tr -d ' ') screenshots are unique ✓"
else
    log "  $dupes duplicate pair(s) found — navigation may have failed for some views"
fi

log ""
log "Done: $OUT_DIR"
open "$OUT_DIR"
