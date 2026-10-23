#!/usr/bin/env bash
# The soak tier (S1): imports assets and runs only the test_soak_* methods (tests/run_tests.gd
# --soak), the long gates that would make tools/check.sh too slow: the golden M1 hashes at 18,000
# ticks and, as the endless world lands, the long swims, seams and samples. CI runs it in the job
# "soak", in parallel with test-and-export; S1 sign-off needs it green on the final commit.
# Usage: tools/check_soak.sh [path-to-godot]
# The soak run has a 3600 s limit (tools/bounded.sh), inside CI's 75-minute job timeout, so a hang
# fails with the output so far. With --only=a,b after the Godot path it runs only those files' soak
# tests (a file with none fails the run, as run_tests.gd does when nothing ran).
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/toolchain.env
GODOT="${1:-${GODOT:-.toolchain/Godot_v${GODOT_RELEASE}_linux.x86_64}}"
shift || true

source tools/bounded.sh

tools/test_bounded.sh
bounded 600 "$GODOT" --headless --path . --import
bounded 3600 "$GODOT" --headless --path . --script res://tests/run_tests.gd -- --soak "$@"
