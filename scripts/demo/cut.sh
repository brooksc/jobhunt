#!/usr/bin/env bash
# Cut the recorded walkthrough into the published assets.
#
#   ./cut.sh <master.mov> <outdir>
#
# The master contains a REAL wait — extraction and scoring against a real provider take about a
# minute. That's honest but unwatchable, so the wait is cut out and the jump is labelled rather than
# hidden: pretending the result is instant would misrepresent the product, since how long it takes
# depends on the model the viewer picks.
set -euo pipefail

SRC="${1:?usage: cut.sh <master.mov> <outdir>}"
OUT="${2:?usage: cut.sh <master.mov> <outdir>}"
mkdir -p "$OUT/cap"

# Offsets on the MASTER timeline, from the driver's SCENE_LOG plus the 1.5s capture head start.
A_START=${A_START:-2.0}; A_END=${A_END:-16.3}    # posting -> capture -> preflight -> job arrives
B_START=${B_START:-96.4}; B_END=${B_END:-119.2}  # extracted + scored -> fit breakdown -> sort by fit
SPEED=${SPEED:-1.30}
FONT="${CAPTION_FONT:-/System/Library/Fonts/HelveticaNeue.ttc}"

# screencapture writes VARIABLE frame rate — it emits a frame when the screen changes, so a static
# window produces almost none. `-ss` then seeks to the nearest keyframe and every offset below lands
# seconds away from where the arithmetic says, which silently slid the captions off the footage they
# describe (a caption about the browser played over the app). Normalise to CFR once, up front, and
# the offsets mean what they say.
ffmpeg -hide_banner -loglevel error -y -i "$SRC" -vf fps=30 -c:v libx264 -crf 16 -an "$OUT/.cfr.mov"
SRC="$OUT/.cfr.mov"

ffmpeg -hide_banner -loglevel error -y -ss "$A_START" -to "$A_END" -i "$SRC" -c:v libx264 -crf 16 -an "$OUT/.a.mov"
ffmpeg -hide_banner -loglevel error -y -ss "$B_START" -to "$B_END" -i "$SRC" -c:v libx264 -crf 16 -an "$OUT/.b.mov"
# Bare filenames, not "$OUT/...": ffmpeg's concat demuxer resolves entries relative to the concat
# file's OWN directory, so a relative outdir doubled the prefix
# ("marketing/demo/marketing/demo/.a.mov") and the cut failed after the capture was already spent.
printf "file '.a.mov'\nfile '.b.mov'\n" > "$OUT/.concat.txt"
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$OUT/.concat.txt" -c copy "$OUT/.joined.mov"

A_LEN=$(python3 -c "print(f'{$A_END-$A_START:.2f}')")

# start|end|text  — on the JOINED timeline (pre-speed).
CAPTIONS=(
  "0.3|3.7|Any job posting. One click."
  "4.1|8.9|It reads the page first — title, salary, location, remote"
  "9.4|13.3|The job lands in JobHunt straight away"
  "13.7|16.6|about a minute later…"
  "17.0|19.9|Everything filled in: company, remote status, salary band"
  "20.4|27.2|And scored against your resume, requirement by requirement"
  "27.8|36.0|Sort by fit — your whole list ranks itself"
)

i=0; FILTER=""; INPUTS=""
for entry in "${CAPTIONS[@]}"; do
  IFS='|' read -r start end text <<< "$entry"
  i=$((i + 1))
  png="$OUT/cap/c$i.png"
  # No -interword-spacing: it collapses the spaces between words.
  magick -background '#000000B8' -fill white -font "$FONT" -pointsize 62 \
         -gravity center -size 2800x label:"$text" \
         -bordercolor '#000000B8' -border 36 "$png"
  INPUTS="$INPUTS -i $png"
  if [ -z "$FILTER" ]; then
    FILTER="[0:v][${i}:v]overlay=(W-w)/2:H-h-90:enable='between(t,$start,$end)'[v$i]"
  else
    FILTER="$FILTER;[v$((i - 1))][${i}:v]overlay=(W-w)/2:H-h-90:enable='between(t,$start,$end)'[v$i]"
  fi
done

# shellcheck disable=SC2086
ffmpeg -hide_banner -loglevel error -y -i "$OUT/.joined.mov" $INPUTS \
  -filter_complex "$FILTER" -map "[v$i]" -c:v libx264 -crf 17 -pix_fmt yuv420p "$OUT/.captioned.mov"

# App Store preview: 1920x1080, must be 15-30s.
ffmpeg -hide_banner -loglevel error -y -i "$OUT/.captioned.mov" \
  -vf "setpts=PTS/$SPEED,scale=1920:1080:flags=lanczos" -an \
  -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart "$OUT/walkthrough-1080p.mp4"

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/walkthrough-1080p.mp4")
python3 -c "
d=$DUR
assert 15 <= d <= 30, f'App Store preview must be 15-30s, got {d:.1f}s'
print(f'walkthrough-1080p.mp4  {d:.1f}s  (App Store limit 15-30s: OK)')
"

gif() { # gif <name> <start> <dur> [width]  — offsets on the CAPTIONED timeline
  local name=$1 start=$2 dur=$3 width=${4:-900}
  local pal="$OUT/.pal.png"
  ffmpeg -hide_banner -loglevel error -y -ss "$start" -t "$dur" -i "$OUT/.captioned.mov" \
    -vf "fps=12,scale=$width:-1:flags=lanczos,palettegen=stats_mode=diff" "$pal"
  ffmpeg -hide_banner -loglevel error -y -ss "$start" -t "$dur" -i "$OUT/.captioned.mov" -i "$pal" \
    -lavfi "fps=12,scale=$width:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
    "$OUT/$name.gif"
  rm -f "$pal"
  printf '%-26s %s\n' "$name.gif" "$(du -h "$OUT/$name.gif" | cut -f1)"
}

gif capture-a-job   0.4 13.0
# Skip the first ~2.6s of segment B. The row isn't selected until scene 05 fires, so B opens on an
# empty "No Job Selected" pane — fine mid-video where the wait is being narrated, but this GIF is
# shown standalone in the README and loops, so it was starting AND ending on nothing.
gif extracted-and-scored "$(python3 -c "print(f'{$A_LEN + 2.6:.2f}')")" 17.4

rm -f "$OUT"/.cfr.mov "$OUT"/.a.mov "$OUT"/.b.mov "$OUT"/.joined.mov "$OUT"/.captioned.mov "$OUT"/.concat.txt
rm -rf "$OUT/cap"
