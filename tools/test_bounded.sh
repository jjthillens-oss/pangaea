#!/usr/bin/env bash
# Checks tools/bounded.sh, the time limit check.sh and check_release.sh put on every Godot run,
# with sleep standing in for a Godot run that hangs (about 15 s; tools/check.sh runs it first):
#   stopped:  a run past its limit stops with exit code 124 and a line naming the limit
#   killed:   a run that ignores the stop is killed 10 s later, exit code 137
#   Ctrl-C:   an interrupt sent to the calling script's process group, as a terminal sends one,
#             stops the run inside it and the script, leaving nothing running (skipped when this
#             script was started with interrupts ignored, as a background job is)
#   stop:     a terminate sent to that group, as an outer timeout or a CI runner sends one, the same
# Usage: tools/test_bounded.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/bounded.sh
if ! command -v timeout > /dev/null; then
  echo "bounded: no coreutils timeout here, so runs have no limit; nothing to check."
  exit 0
fi
failed=0
fail() {
  echo "FAIL bounded: $*"
  failed=1
}

# stopped
out="$(bounded 1 sleep 30)" && status=0 || status=$?
[ "$status" -eq 124 ] || fail "a run past its 1 s limit ended with status $status, not 124"
[ "$out" = "Stopped after its 1 s limit: sleep 30" ] || fail "a stopped run printed '$out'"

# killed
out="$(bounded 1 bash -c 'trap "" TERM; exec sleep 30')" && status=0 || status=$?
[ "$status" -eq 137 ] || fail "a run that ignores the stop ended with status $status, not 137"

# Ctrl-C and stop: a script like check.sh, in a process group of its own (job control on), runs a
# sleep with a name no other process has under a 60 s limit; the signal goes to the whole group.
signal_group() {
  local signal="$1"
  local nap="29.$$$RANDOM"
  set -m
  bash -c 'source tools/bounded.sh; bounded 60 sleep "$1"; echo "still running after the $2"' _ "$nap" "$signal" &
  local script=$!
  set +m
  local _
  for _ in $(seq 100); do
    pgrep -f "^sleep $nap\$" > /dev/null && break
    sleep 0.05
  done
  kill -s "$signal" -- "-$script"
  # Until the script has ended (a zombie, or gone), for up to 3 s.
  for _ in $(seq 60); do
    case "$(ps -o stat= -p "$script" || true)" in "" | Z*) break ;; esac
    sleep 0.05
  done
  case "$(ps -o stat= -p "$script" || true)" in
    "" | Z*) ;;
    *)
      fail "SIG$signal to the script's process group left the script waiting on its bounded run"
      kill -s KILL -- "-$script" 2> /dev/null || true
      ;;
  esac
  local status=0
  wait "$script" 2> /dev/null || status=$?
  [ "$status" -ne 0 ] || fail "the script carried on after SIG$signal"
  for _ in $(seq 20); do
    pgrep -f "^sleep $nap\$" > /dev/null || return 0
    sleep 0.05
  done
  fail "SIG$signal to the script's process group left its bounded run going"
  pkill -f "^sleep $nap\$" || true
}
if [ -n "$(trap -p INT)" ]; then
  echo "bounded: interrupts were ignored when this started, so the Ctrl-C check is skipped."
else
  signal_group INT
fi
signal_group TERM

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "bounded: stops, kills, Ctrl-C and outer stops all work."
