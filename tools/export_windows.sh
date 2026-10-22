#!/usr/bin/env bash
# Exports builds/windows/Pangaea.exe with the pinned templates. Usage: tools/export_windows.sh [path-to-godot]
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/toolchain.env
GODOT="${1:-${GODOT:-.toolchain/Godot_v${GODOT_RELEASE}_linux.x86_64}}"
tools/write_build_info.sh
mkdir -p builds/windows
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release "Windows Desktop" builds/windows/Pangaea.exe
ls -la builds/windows
