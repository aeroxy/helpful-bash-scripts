#!/usr/bin/env bash
# Remove the last 90 video frames from a video. Writes <name>_trimmed.<ext>
# next to the input, replacing an earlier one, and leaves the input untouched.
#   usage: cut_last_90f.sh <video>
set -euo pipefail

FRAMES=90

if [ $# -ne 1 ]; then
  echo "usage: $(basename "$0") <video>" >&2
  exit 2
fi

in=$1
if [ ! -f "$in" ]; then
  echo "error: no such file: $in" >&2
  exit 2
fi

base=$(basename "$in")
case $base in
  *.*) ;;
  *) echo "error: $base has no extension, so the output format is unknown" >&2; exit 2 ;;
esac
name=${base%.*}
ext=${base##*.}
out="$(dirname "$in")/${name}_trimmed.$ext"

# One timestamp per decoded frame, in display order. Counting them gives the
# exact frame count, and the timestamp of the first dropped frame is where the
# audio has to end, which also holds for variable-frame-rate video.
ts=$(ffprobe -v error -select_streams v:0 \
  -show_entries frame=best_effort_timestamp_time -of csv=p=0 "$in")
total=$(printf '%s\n' "$ts" | awk 'NF { n++ } END { print n + 0 }')
keep=$((total - FRAMES))
if [ "$keep" -le 0 ]; then
  echo "error: $base has $total frames, so removing $FRAMES would leave nothing" >&2
  exit 1
fi
start=$(printf '%s\n' "$ts" | sed -n 1p)
cut=$(printf '%s\n' "$ts" | sed -n "$((keep + 1))p")
duration=$(awk -v a="$start" -v b="$cut" 'BEGIN { printf "%.6f", b - a }')

# Only mp4/mov containers understand faststart. Left unquoted below on purpose,
# so it expands to two arguments or none.
faststart=""
case $ext in
  mp4|MP4|mov|MOV|m4v|M4V) faststart="-movflags +faststart" ;;
esac

# The video is re-encoded because copying it could only cut at a keyframe.
# The audio is copied, so it ends within one audio frame (~23 ms) of the cut.
ffmpeg -hide_banner -v error -y -i "$in" \
  -map 0:v:0 -map '0:a?' \
  -frames:v "$keep" -t "$duration" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -c:a copy $faststart \
  "$out"

echo "kept $keep of $total frames ($duration s): $out"
