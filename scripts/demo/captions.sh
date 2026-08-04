#!/usr/bin/env bash
# Burn captions into the master recording and emit .srt / .vtt alongside.
#
# This Homebrew ffmpeg is built WITHOUT libfreetype and libass, so `drawtext` and `subtitles` do not
# exist (check: `ffmpeg -filters | grep drawtext`). Captions are therefore rendered to PNGs with
# ImageMagick and composited with overlay + enable='between(t,a,b)'.
#
#   ./captions.sh <master.mov> <outdir>
set -euo pipefail

MASTER="${1:?usage: captions.sh <master.mov> <outdir>}"
OUT="${2:?usage: captions.sh <master.mov> <outdir>}"
mkdir -p "$OUT/cap"

# ImageMagick's default font is unresolved on this machine ("unable to read font ''"), so the face is
# always passed explicitly.
FONT="${CAPTION_FONT:-/System/Library/Fonts/HelveticaNeue.ttc}"
W=3200

# start end text   — times are in seconds on the MASTER timeline, taken from the driver's SCENE_LOG
# plus the capture head-start, never guessed from the script.
CAPTIONS=(
  "1.7|4.2|Every job you capture, scored against your résumé"
  "4.4|9.2|Salary, location and requirements — pulled out automatically"
  "9.4|14.8|Per requirement: what you have, what you don't, and the evidence"
  "15.0|21.4|Disagree? Correct it right where you see it"
  "21.6|26.6|The gap moves to met — instantly, with no AI call"
  "26.8|32.5|Reopen the job: 84 becomes 94"
  "32.7|38.2|One correction applies to every job, not just this one"
  "38.5|43.8|Runs on your Mac, with the model you choose"
)

i=0
FILTER=""
INPUTS=""
for entry in "${CAPTIONS[@]}"; do
  IFS='|' read -r start end text <<< "$entry"
  i=$((i + 1))
  png="$OUT/cap/c$i.png"
  # Do NOT pass -interword-spacing to `label:` — it collapses the spaces between words.
  magick -background '#000000B3' -fill white -font "$FONT" -pointsize 62 \
         -gravity center -size $((W - 400))x label:"$text" \
         -bordercolor '#000000B3' -border 36 "$png"
  INPUTS="$INPUTS -i $png"
  i_in=$i
  if [ -z "$FILTER" ]; then
    FILTER="[0:v][${i_in}:v]overlay=(W-w)/2:H-h-90:enable='between(t,$start,$end)'[v$i_in]"
  else
    FILTER="$FILTER;[v$((i_in - 1))][${i_in}:v]overlay=(W-w)/2:H-h-90:enable='between(t,$start,$end)'[v$i_in]"
  fi
done

# shellcheck disable=SC2086
ffmpeg -hide_banner -loglevel error -y -i "$MASTER" $INPUTS \
  -filter_complex "$FILTER" -map "[v$i]" -c:v libx264 -crf 18 -pix_fmt yuv420p \
  "$OUT/master-captioned.mov"

# Burned-in captions are not accessible, and a web <track> needs a real file.
srt="$OUT/walkthrough.srt"
vtt="$OUT/walkthrough.vtt"
: > "$srt"
printf 'WEBVTT\n\n' > "$vtt"
ts() { printf '%02d:%02d:%06.3f' $(($1 / 3600)) $((($1 % 3600) / 60)) "$(echo "$1 - ($1 / 60 * 60)" | bc -l 2>/dev/null || echo "$1")"; }
n=0
for entry in "${CAPTIONS[@]}"; do
  IFS='|' read -r start end text <<< "$entry"
  n=$((n + 1))
  s=$(python3 -c "t=$start; print(f'{int(t//3600):02d}:{int(t%3600//60):02d}:{t%60:06.3f}')")
  e=$(python3 -c "t=$end;   print(f'{int(t//3600):02d}:{int(t%3600//60):02d}:{t%60:06.3f}')")
  printf '%d\n%s --> %s\n%s\n\n' "$n" "${s/./,}" "${e/./,}" "$text" >> "$srt"
  printf '%s --> %s\n%s\n\n' "$s" "$e" "$text" >> "$vtt"
done

echo "wrote $OUT/master-captioned.mov, $srt, $vtt"
