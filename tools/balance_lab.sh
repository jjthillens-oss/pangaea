#!/usr/bin/env bash
# The balance lab: runs the dev bots (forage, wary, evade, hunt, kiter) for every starting body over
# a range of seeds, headless, in parallel shards, and writes builds/balance/report.md (a table per
# body and bot: survival, deaths and their causes, meals, starving, threat meetings, dodges, kills)
# and builds/balance/balance.json (every run). It reads the sim and never changes it; the report is
# information, not a gate (game/dev/balance_lab.gd, tests/balance/balance_lab_main.gd).
# Usage: tools/balance_lab.sh [--seeds=1001-1008] [--seconds=300] [--bodies=a,b] [--bots=a,b] [--jobs=N]
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/toolchain.env
GODOT="${GODOT:-.toolchain/Godot_v${GODOT_RELEASE}_linux.x86_64}"
source tools/bounded.sh

JOBS="$(nproc)"
ARGS=()
for a in "$@"; do
  case "$a" in
    --jobs=*) JOBS="${a#--jobs=}" ;;
    *) ARGS+=("$a") ;;
  esac
done
OUT=builds/balance
rm -rf "$OUT"
mkdir -p "$OUT"
# Each shard has an hour; a default sweep (120 runs of 300 s) takes about a quarter of that on 4 CPUs.
pids=()
for ((i = 0; i < JOBS; i++)); do
  bounded 3600 "$GODOT" --headless --path . --script res://tests/balance/balance_lab_main.gd -- \
    "${ARGS[@]}" --shard="$i/$JOBS" --out="$OUT/shard_$i.json" > "$OUT/shard_$i.log" 2>&1 &
  pids+=($!)
done
status=0
for p in "${pids[@]}"; do wait "$p" || status=1; done
if [ "$status" -ne 0 ]; then
  echo "A balance lab shard failed; see $OUT/shard_*.log"
  tail -n 20 "$OUT"/shard_*.log
  exit 1
fi
bounded 300 "$GODOT" --headless --path . --script res://tests/balance/balance_lab_main.gd -- --merge="$OUT" --report="$OUT/report.md"
cat "$OUT/report.md"
