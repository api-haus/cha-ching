#!/usr/bin/env bash
# The Kimi drive: everything AGENTS.md §Testing says is worth asserting about
# the main wire and the subagent wires, rebuilt from that text.
set -u
. "$(dirname "$0")/lib.sh"

K3='3 0.3 3 15'                 # input cache_read cache_write output, $/M
FC='9 0.9 9 45'                 # a second, deliberately unlike, rate
export RTC_PRICE_kimi_code_k3="$K3"

printf '\n== main wire ==\n'
fresh main
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
row "$M" 1207 55000 0 537
render >/dev/null
is 'first render adopts the wire, announces nothing' 0 "$(cost)"

row "$M" 1207 55000 0 537
render >/dev/null
# 1207*3 + 55000*0.3 + 0*3 + 537*15 over a million
near 'an appended row is priced and lands' 0.028176 "$(cost)"

render >/dev/null
near 'a render with no new rows adds nothing' 0.028176 "$(cost)"

n0=$(wc -l < "$XDG_RUNTIME_DIR/rtc-kimi-$SESS.rebuilds" 2>/dev/null || echo 0)
row "$M" 100 1000 90000 200
render >/dev/null
n1=$(wc -l < "$XDG_RUNTIME_DIR/rtc-kimi-$SESS.rebuilds" 2>/dev/null || echo 0)
is 'a cache-rebuild row files under .rebuilds' "$((n0 + 1))" "$((n1))"

printf '\n== no rate at all ==\n'
fresh noprice
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
row "$M" 1207 55000 0 537 'kimi-code/unpriced'
render >/dev/null
row "$M" 1207 55000 0 537 'kimi-code/unpriced'
out=$(render)
case "$out" in *'$'*) bad 'money vanishes whole with no rate' 'no $ in the segment' "$out" ;;
               *)     ok 'money vanishes whole with no rate' ;; esac
case "$out" in *'%'*) ok 'the gauge still renders' ;; *) bad 'the gauge still renders' '%' "$out" ;; esac
export RTC_PRICE_kimi_code_unpriced="$K3"
out=$(render)
case "$out" in *'$'*) ok 'money returns once a rate exists' ;;
               *)     bad 'money returns once a rate exists' '$' "$out" ;; esac
unset RTC_PRICE_kimi_code_unpriced

printf '\n== subagent wires ==\n'
fresh subs
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
A0="$SDIR/agents/agent-0/wire.jsonl"; mkdir -p "$(dirname "$A0")"; : > "$A0"
row "$M"  1000 50000 0 500
row "$A0" 2000 40000 0 900          # history: present before rtc ever looked
render >/dev/null
is 'a wire present at the first render is adopted' 0 "$(cost)"
is '  and none of it is called subagent money' 0 "$(sacc)"

# A wire that appears later is a subagent just spawned: every byte is ours.
A1="$SDIR/agents/agent-1/wire.jsonl"; mkdir -p "$(dirname "$A1")"
row "$A1" 3000 30000 0 700
render >/dev/null
near 'a wire appearing later counts from byte 0' 0.028500 "$(cost)"
near '  and all of it is subagent money' 0.028500 "$(sacc)"

# Each row priced by the model it names, not by the session's.
export RTC_PRICE_kimi_code_kimi_for_coding="$FC"
row "$A0" 1000 10000 0 100 'kimi-code/kimi-for-coding'
row "$A1" 1000 10000 0 100
render >/dev/null
# agent-0 at the second rate: 9000 + 9000 + 4500 = 0.0225
# agent-1 at k3:              3000 +  3000 + 1500 = 0.0075
near 'two wires, two models, each priced by its own' 0.058500 "$(cost)"

# A row being written at this moment is left alone until its newline lands.
printf '%s' '{"type":"usage.record","model":"kimi-code/k3","usage":{"inputOther":5000,"output":0,"inputCacheRead":0,"inputCacheCreation":0},"usageScope":"turn"' >> "$A1"
render >/dev/null
near 'a partial trailing line is not counted' 0.058500 "$(cost)"
printf '%s\n' ',"time":9}' >> "$A1"
render >/dev/null
near '  and is counted once the newline lands' 0.073500 "$(cost)"

# A wire replaced by a shorter file rotated; adopt, never recount.
before=$(cost)
: > "$A1"
row "$A1" 1 0 0 0
render >/dev/null
near 'a shortened wire adopts instead of recounting' "$before" "$(cost)"
row "$A1" 1000000 0 0 0
render >/dev/null
near '  and counts what arrives after the adoption' \
  "$(awk -v b="$before" 'BEGIN { printf "%.6f", b + 3 }')" "$(cost)"

printf '\n== the estimate is taught the main bump alone ==\n'
fresh sample
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
A0="$SDIR/agents/agent-0/wire.jsonl"; mkdir -p "$(dirname "$A0")"; : > "$A0"
row "$M" 1 0 0 0
render >/dev/null
row "$M"  1000 50000 0 500          # main:     3000 + 15000 + 7500 = 0.0255
row "$A0" 9000 90000 0 9000         # subagent: 27000 + 27000 + 135000 = 0.189
render >/dev/null
near 'the total carries both' 0.214500 "$(cost)"
near 'sacc carries the subagent share' 0.189000 "$(sacc)"
# ctx is 55000, so the sample is the main bump per million tokens of context.
last_sample=$(tail -1 "$XDG_RUNTIME_DIR/rtc-kimi-$SESS.turns")
near 'the .turns sample is the MAIN bump, not the total' \
  "$(awk 'BEGIN { printf "%.6f", 0.0255 / 0.055 }')" "$last_sample" 0.0005

report
