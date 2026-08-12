#!/usr/bin/env bash
# Idle renders, which is the steady state: the statusline is paid once a second
# for every open session whether or not anything happened.
set -u
. "$(dirname "$0")/lib.sh"
export RTC_PRICE_kimi_code_k3='3 0.3 3 15'
SRC=$HOME/.kimi-code/sessions/wd_swordgal_3454979383bf/session_7e49b95f-1e7d-4a3c-b716-4034fa9267ad

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

fresh bench4
rm -rf "$W/kimi/sessions/proj/$SESS"
cp -r "$SRC" "$W/kimi/sessions/proj/$SESS"
bench "$(ls -d "$W/kimi/sessions/proj/$SESS"/agents/agent-* | wc -l | tr -d ' ') subagent wires" 40
