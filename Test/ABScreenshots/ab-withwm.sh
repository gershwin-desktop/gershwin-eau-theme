#!/bin/sh
# ab-withwm.sh - run a command under a window manager on the current display
#
# SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
#
# usage: ab-withwm.sh WM_BINARY WM_LOG COMMAND [ARGS...]
# Passed to xvfb-run by ab-compare.sh: starts the window manager, waits until
# it has taken over the root window, runs COMMAND and stops the manager again.
# WM_ARGS (environment) are extra arguments for the window manager.
HERE=$(cd "$(dirname "$0")" && pwd)
wm=$1 log=$2
shift 2
# shellcheck disable=SC2086
"$wm" $WM_ARGS > "$log" 2>&1 &
pid=$!
if ! "$HERE/obj/abinput" waitwm 30; then
  echo "ab-withwm: $wm did not take over the display" >&2
  kill -9 $pid 2>/dev/null
  exit 75
fi
# Let the manager finish adopting the root window before the first client.
sleep 1
"$@"
status=$?
kill $pid 2>/dev/null
sleep 1
kill -9 $pid 2>/dev/null
exit $status
