#!/usr/bin/env bash
# What several processes do to one file at the same moment — the only thing a
# replayed wire can never show. Two shapes: ten sessions piling onto the shared
# ring, and a subagent writing its wire while renders land on it.
set -u
. "$(dirname "$0")/lib.sh"
export RTC_MUTE=0

# One dollar per input token, so the arithmetic below is countable by eye.
export RTC_PRICE_kimi_code_k3='1000000 0 0 0'

printf '\n== ten sessions, one ring ==\n'
SESS=s0
fresh conc
export RTC_RING_SCOPE=global RTC_RING=cumulative_threshold RTC_THRESHOLD=5

spend() {                       # spend <session> — $5, five dollars at a time
  local s=$1 i
  local d="$W/kimi/sessions/proj/$s/agents/main"
  mkdir -p "$d"; : > "$d/wire.jsonl"
  SESS=$s
  render >/dev/null                                   # adopt
  for i in 1 2 3 4 5; do
    row "$d/wire.jsonl" 1 0 0 0
    render >/dev/null
  done
  render >/dev/null; render >/dev/null                # let a late ring land
}

for n in 0 1 2 3 4 5 6 7 8 9; do ( spend "s$n" ) & done
wait
sleep 0.6
is '$50 across ten concurrent sessions at $5 rings exactly ten times' 10 "$(rings)"
read -r gts gacc < "$XDG_RUNTIME_DIR/rtc-global-${UID:-0}.ring"
near 'and nothing is left carried in the shared accumulator' 0 "${gacc:-x}" 0.0001
left=0
for n in 0 1 2 3 4 5 6 7 8 9; do
  v=$(cut -d' ' -f11 < "$XDG_RUNTIME_DIR/rtc-kimi-s$n.state")
  left=$(awk -v a="$left" -v b="${v:-0}" 'BEGIN { printf "%.6f", a + b }')
done
near 'and no session is still holding money it failed to hand over' 0 "$left" 0.0001
tot=0
for n in 0 1 2 3 4 5 6 7 8 9; do
  v=$(cut -d' ' -f1 < "$XDG_RUNTIME_DIR/rtc-kimi-s$n.state")
  tot=$(awk -v a="$tot" -v b="${v:-0}" 'BEGIN { printf "%.6f", a + b }')
done
near 'and every dollar is still on a session total' 50 "$tot" 0.0001

printf '\n== a subagent writing while renders land on it ==\n'
export RTC_MUTE=1 RTC_RING_SCOPE=session
SESS=live; fresh live >/dev/null
export RTC_PRICE_kimi_code_k3='3 0.3 3 15'
export RTC_PRICE_kimi_code_kimi_for_coding='9 0.9 9 45'
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
mkdir -p "$SDIR/agents/agent-0" "$SDIR/agents/agent-1"
: > "$SDIR/agents/agent-0/wire.jsonl"; : > "$SDIR/agents/agent-1/wire.jsonl"
render >/dev/null                                     # adopt three empty wires

# The writer splits every row across two writes, so a render landing between
# them sees a line with no newline on the end — the case the offset rule exists
# for. agent-2 does not exist yet: it is spawned mid-flight.
writer() {
  local i w model
  for i in $(seq 1 60); do
    case $((i % 4)) in
      0) w="$SDIR/agents/main/wire.jsonl";    model=kimi-code/k3 ;;
      1) w="$SDIR/agents/agent-0/wire.jsonl"; model=kimi-code/k3 ;;
      2) w="$SDIR/agents/agent-1/wire.jsonl"; model=kimi-code/kimi-for-coding ;;
      3) mkdir -p "$SDIR/agents/agent-2"
         w="$SDIR/agents/agent-2/wire.jsonl"; model=kimi-code/k3 ;;
    esac
    printf '{"type":"usage.record","model":"%s","usage":{"inputOther":1000,"output":100,' "$model" >> "$w"
    sleep 0.01
    printf '"inputCacheRead":5000,"inputCacheCreation":0},"usageScope":"turn","time":%s}\n' "$i" >> "$w"
    sleep 0.02
  done
  : > "$W/writer.done"
}

writer &
wpid=$!
while [ ! -e "$W/writer.done" ]; do render >/dev/null; sleep 0.05; done
wait $wpid
render >/dev/null; render >/dev/null                  # drain the last partial line

want=$(sumdir "$SDIR" 'kimi-code/k3=3,0.3,3,15' 'kimi-code/kimi-for-coding=9,0.9,9,45')
near 'the total agrees with a sum over every row in every wire' "$want" "$(cost)" 0.000002
nsub=$(wc -l < "$XDG_RUNTIME_DIR/rtc-kimi-$SESS.subs" | tr -d ' ')
is 'the wire spawned mid-flight is being tailed' 3 "$((nsub))"
# main wrote 15 of the 60 rows, all k3: 15 x (3000 + 1500 + 1500) / 1e6
near 'and the subagent share excludes what main spent' \
  "$(awk -v t="$want" 'BEGIN { printf "%.6f", t - 15 * 0.006 }')" "$(sacc)" 0.000002

report
