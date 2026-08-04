#!/usr/bin/env bash
# Produce the deliverables from the captioned master:
#   walkthrough-1080p.mp4   App Store preview — 1920x1080, must be 15-30s
#   *.gif                   README/site clips, two-pass palettegen/paletteuse
#
#   ./encode.sh <master-captioned.mov> <outdir>
set -euo pipefail

SRC="${1:?usage: encode.sh <master-captioned.mov> <outdir>}"
OUT="${2:?usage: encode.sh <master-captioned.mov> <outdir>}"
mkdir -p "$OUT"

# App Store Connect rejects anything over 30s. The master runs ~46s, so trim the dead tail after the
# last scene and speed up rather than cutting the payoff — 1.5x still reads comfortably.
TRIM="${TRIM:-44.2}"
SPEED="${SPEED:-1.5}"

# -t must come BEFORE -i. As an output option it caps the OUTPUT duration, which the sped-up
# stream is already under, so the trim silently does nothing and the preview comes out over 30s.
ffmpeg -hide_banner -loglevel error -y -t "$TRIM" -i "$SRC" \
  -vf "setpts=PTS/$SPEED,scale=1920:1080:flags=lanczos" -an \
  -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart \
  "$OUT/walkthrough-1080p.mp4"

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/walkthrough-1080p.mp4")
echo "walkthrough-1080p.mp4  ${DUR}s"
python3 -c "
d=$DUR
assert 15 <= d <= 30, f'App Store preview must be 15-30s, got {d:.1f}s'
print(f'  duration OK ({d:.1f}s, within 15-30s)')
"

gif() { # gif <name> <start> <duration> [width]
  local name=$1 start=$2 dur=$3 width=${4:-1000}
  local pal="$OUT/.pal-$name.png"
  ffmpeg -hide_banner -loglevel error -y -ss "$start" -t "$dur" -i "$SRC" \
    -vf "fps=13,scale=$width:-1:flags=lanczos,palettegen=stats_mode=diff" "$pal"
  ffmpeg -hide_banner -loglevel error -y -ss "$start" -t "$dur" -i "$SRC" -i "$pal" \
    -lavfi "fps=13,scale=$width:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
    "$OUT/$name.gif"
  rm -f "$pal"
  printf '%-28s %s\n' "$name.gif" "$(du -h "$OUT/$name.gif" | cut -f1)"
}

# Offsets are on the MASTER timeline (see scenes.txt + the 1.5s capture head start).
gif fit-breakdown   9.3  5.6
gif correct-a-gap  14.9  9.6 860
gif score-updates  26.7  7.4
