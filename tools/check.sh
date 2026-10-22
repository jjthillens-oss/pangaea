#!/usr/bin/env bash
# Imports assets, runs the test suite and the boot smoke check. Usage: tools/check.sh [path-to-godot]
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/toolchain.env
GODOT="${1:-${GODOT:-.toolchain/Godot_v${GODOT_RELEASE}_linux.x86_64}}"
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://tests/run_tests.gd
"$GODOT" --headless --path . -- --smoke
