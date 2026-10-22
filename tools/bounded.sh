# Sourced by tools/check.sh and tools/check_release.sh; tools/test_bounded.sh checks it.
# bounded SECONDS COMMAND...: runs COMMAND, stopped after SECONDS (killed 10 s later if it ignores
# the stop), and returns its status: 124 when stopped, 137 when killed, after a line naming the
# limit. timeout runs with --foreground, so COMMAND stays in the script's process group: a Ctrl-C at
# the terminal, or a stop that an outer timeout or a CI runner sends to the group, reaches it, and
# no Godot keeps running after the script has gone. (Without it timeout moves COMMAND to a group of
# its own, out of reach.) The cost: a process COMMAND starts is not stopped with it, and none of
# the Godot runs here start one. Without coreutils' timeout (macOS) COMMAND runs with no limit.
bounded() {
  local limit="$1"
  shift
  if ! command -v timeout > /dev/null; then
    "$@"
    return
  fi
  local status=0
  timeout --foreground --kill-after=10 "$limit" "$@" || status=$?
  if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
    echo "Stopped after its ${limit} s limit: $*"
  fi
  return "$status"
}
