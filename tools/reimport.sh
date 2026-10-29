#!/usr/bin/env bash
# Rebuilds Godot's global class cache (.godot/) — run after adding/renaming class_name scripts.
cd "$(dirname "$0")/.." && godot --headless --import --path . 2>&1 | grep -E "ERROR|SCRIPT ERROR|Parse Error|error" | grep -v "ALSA" || true
