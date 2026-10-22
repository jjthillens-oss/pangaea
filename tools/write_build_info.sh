#!/usr/bin/env bash
# Writes game/data/build_info.json so an exported build can report which commit it came from.
set -euo pipefail
cd "$(dirname "$0")/.."
commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then commit="${commit}-dirty"; fi
printf '{\n\t"commit": "%s",\n\t"built_at": "%s"\n}\n' "$commit" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > game/data/build_info.json
cat game/data/build_info.json
