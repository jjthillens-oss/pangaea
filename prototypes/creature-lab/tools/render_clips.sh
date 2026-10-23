#!/usr/bin/env bash
# Renders the Gait Lab demo drive for each body as a 10 s MP4 and a contact sheet (Xvfb + Compatibility renderer).
# Usage: prototypes/creature-lab/tools/render_clips.sh OUT_DIR
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="${1:?usage: render_clips.sh OUT_DIR}"
mkdir -p "$out"
godot="$repo/.toolchain/Godot_v4.7.2-stable_linux.x86_64"

for body in quad_short quad_long hexapod all; do
	xvfb-run -a -s "-screen 0 1280x720x24" "$godot" --path "$here" --rendering-method gl_compatibility \
		--rendering-driver opengl3 --resolution 1280x720 --fixed-fps 60 --write-movie "$out/$body.avi" \
		-- --body="$body" --drive=demo --duration=10 >/dev/null 2>&1
	ffmpeg -loglevel error -y -i "$out/$body.avi" -r 30 -c:v libx264 -pix_fmt yuv420p -crf 23 "$out/gait_lab_$body.mp4"
	# One frame per second, 5 x 2.
	ffmpeg -loglevel error -y -i "$out/$body.avi" -vf "fps=1,scale=640:-1,tile=5x2" -frames:v 1 \
		"$out/gait_lab_${body}_sheet.png"
	rm "$out/$body.avi"
done
ls -la "$out"
