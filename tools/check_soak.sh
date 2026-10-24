#!/usr/bin/env bash
# The soak tier (S1): imports assets and runs only the test_soak_* methods (tests/run_tests.gd
# --soak), the long gates that would make tools/check.sh too slow: the golden M1 hashes at 18,000
# ticks and, as the endless world lands, the long swims, seams and samples. S1 sign-off needs it
# green on the final commit.
# Usage: tools/check_soak.sh [path-to-godot] [--only=a,b | --skip=a,b]
# The runner flags may come without the Godot path. CI runs it twice, in parallel with
# test-and-export (S1 build plan B-14): job soak-a with --only=test_endless_gates,test_endless_cost
# (the endless gates and cost cases), job soak-b with --skip= the same two files (everything else,
# so a new soak file lands there without a list edit). A name that matches no file fails the run,
# as does a run in which nothing ran (tests/run_tests.gd).
# Each soak run has a 3600 s limit (tools/bounded.sh), inside CI's 75-minute job timeout, so a hang
# fails with the output so far. A job that measures over 60 minutes moves its longest samples to a
# nightly workflow (B-14).
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/toolchain.env
GODOT_PATH=""
if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then
  GODOT_PATH="$1"
  shift
fi
GODOT="${GODOT_PATH:-${GODOT:-.toolchain/Godot_v${GODOT_RELEASE}_linux.x86_64}}"

source tools/bounded.sh

tools/test_bounded.sh
bounded 600 "$GODOT" --headless --path . --import
bounded 3600 "$GODOT" --headless --path . --script res://tests/run_tests.gd -- --soak "$@"
