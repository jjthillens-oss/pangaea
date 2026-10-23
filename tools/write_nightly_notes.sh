#!/usr/bin/env bash
# Prints the WHATS_NEW.txt that ships in a nightly zip: the commit it was built from and what main
# gained since the previous nightly (main's own commits, so each merged PR is one line).
# Usage: tools/write_nightly_notes.sh [previous-nightly-commit]   (none: the last 15 on main)
set -euo pipefail
cd "$(dirname "$0")/.."
previous="${1:-}"
head="$(git rev-parse --short HEAD)"
echo "Pangaea nightly build"
echo "Built from main at $head ($(git log -1 --format=%cs HEAD)) on $(date -u +%Y-%m-%d)."
echo
echo "Run Pangaea.exe to play. Pangaea-dev.exe is the same game with the debug panel and dev keys."
echo "Before publishing, CI ran the tests and smokes, and started both exes on a Windows runner"
echo "(headless and with its software renderer). It has not been played on a real Windows PC yet."
echo
if [ -n "$previous" ] && git cat-file -e "$previous^{commit}" 2> /dev/null; then
  echo "New since the last nightly ($(git rev-parse --short "$previous")):"
  range="$previous..HEAD"
else
  echo "Latest changes on main:"
  range="-15 HEAD"
fi
# shellcheck disable=SC2086
git log --first-parent --format="- %s (%h)" $range
