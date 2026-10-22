#!/usr/bin/env bash
# Downloads the pinned Godot editor (and, with --templates, the export templates) into .toolchain/.
# Linux x86_64 only; on Windows install the same versions by hand (see docs/TOOLCHAIN.md).
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/toolchain.env
mkdir -p .toolchain
GODOT=".toolchain/Godot_v${GODOT_RELEASE}_linux.x86_64"
if [ ! -x "$GODOT" ]; then
  curl -fsSL -o .toolchain/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}/Godot_v${GODOT_RELEASE}_linux.x86_64.zip"
  unzip -oq .toolchain/godot.zip -d .toolchain && rm .toolchain/godot.zip
fi
"$GODOT" --headless --version
if [ "${1:-}" = "--templates" ]; then
  dest="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
  if [ ! -f "$dest/windows_release_x86_64.exe" ]; then
    curl -fsSL -o .toolchain/templates.tpz "https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}/Godot_v${GODOT_RELEASE}_export_templates.tpz"
    mkdir -p "$dest"
    unzip -oj .toolchain/templates.tpz 'templates/windows_release_x86_64.exe' 'templates/windows_debug_x86_64.exe' 'templates/version.txt' -d "$dest"
    rm .toolchain/templates.tpz
  fi
fi
