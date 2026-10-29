#!/usr/bin/env bash
# Runs a tool script with a real (software) renderer for screenshots.
#   tools/shot.sh tools/preview_bones.gd -- all res://screenshots/tmp/bones.png
cd "$(dirname "$0")/.."
script="$1"; shift
res="${SHOT_RES:-1280x720}"
timeout "${SHOT_TIMEOUT:-120}" xvfb-run -a -s "-screen 0 ${res}x24" godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --audio-driver Dummy --resolution "$res" -s "$script" "$@" 2>&1 | grep -v "ALSA\|V-Sync\|vsync\|set_use_vsync"
