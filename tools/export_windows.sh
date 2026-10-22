#!/usr/bin/env bash
# Exports builds/windows/Pangaea.exe (release, without game/dev) and builds/windows/Pangaea-dev.exe
# (debug, with the debug panel and dev keys) with the pinned templates.
# Usage: tools/export_windows.sh [path-to-godot]
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/toolchain.env
GODOT="${1:-${GODOT:-.toolchain/Godot_v${GODOT_RELEASE}_linux.x86_64}}"
tools/write_build_info.sh
mkdir -p builds/windows
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Windows Desktop" builds/windows/Pangaea.exe
"$GODOT" --headless --path . --export-debug "Windows Desktop Dev" builds/windows/Pangaea-dev.exe
ls -la builds/windows
