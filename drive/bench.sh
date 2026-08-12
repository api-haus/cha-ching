#!/usr/bin/env bash
# Idle renders, which is the steady state: the statusline is paid once a second
# for every open session whether or not anything happened. Anything added to
# the render path is paid there, so measure it here before believing it is free.
#
# Compare two builds by pointing RTC at each in turn:
#   RTC=/path/to/old/bin/rtc BASE=/tmp/rtc-drive/old ./drive/bench.sh
set -u
. "$(dirname "$0")/lib.sh"
export RTC_PRICE_kimi_code_k3='3 0.3 3 15'

bench() {                       # bench <label> <n>
  local i=0 t0 t1
  render >/dev/null             # warm: adopt, write the sidecar
  render >/dev/null
  t0=$(date +%s.%N)
  while [ "$i" -lt "$2" ]; do render >/dev/null; i=$((i + 1)); done
  t1=$(date +%s.%N)
  awk -v a="$t0" -v b="$t1" -v n="$2" -v l="$1" \
    'BEGIN { printf "  %-28s %.1fms per render\n", l, (b - a) * 1000 / n }'
}

fresh bench0
bench 'no subagents' 40

# The many-wire figure needs real wires. Whichever session on this machine has
# the most of them will do — the point is the per-wire cost, not whose they are.
SRC=${SRC:-$(real_session)}
if [ -z "${SRC:-}" ]; then
  skip 'the subagent figure' 'no Kimi session with subagent wires'
  exit 0
fi
fresh benchN
rm -rf "$W/kimi/sessions/proj/$SESS"
cp -r "$SRC" "$W/kimi/sessions/proj/$SESS"
bench "$(($(ls -d "$W/kimi/sessions/proj/$SESS"/agents/agent-* | wc -l))) subagent wires" 40
