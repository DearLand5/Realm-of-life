#!/usr/bin/env bash
# Runs the headless test suite. Optional filter: tools/test.sh anatomy
cd "$(dirname "$0")/.." && godot --headless --path . -s tests/run_tests.gd -- "$@" 2>&1 | grep -v "ALSA\|audio driver\|init_output_device\|snd_" 
exit ${PIPESTATUS[0]}
