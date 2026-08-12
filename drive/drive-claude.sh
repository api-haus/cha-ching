#!/usr/bin/env bash
# The Claude side, and with it every path the Kimi drive never touches: the
# once-per-turn TTL read (tac, or tail -r where there is no tac), the band
# hook, the halt marker, doctor, and a setup/uninstall round trip.
set -u
. "$(dirname "$0")/lib.sh"

CSESS=ct
cstate() { cut -d' ' -f"$1" < "$XDG_RUNTIME_DIR/rtc-$CSESS.state" 2>/dev/null; }

cpay() {                        # cpay <prompt_id> <cost> [used] [cache_read]
  printf '{"session_id":"%s","model":{"display_name":"Opus 5","id":"claude-opus-5"},"prompt_id":"%s","transcript_path":"%s","cost":{"total_cost_usd":%s},"context_window":{"total_input_tokens":%s,"context_window_size":1000000,"current_usage":{"cache_creation_input_tokens":900,"cache_read_input_tokens":%s}}}' \
    "$CSESS" "$1" "$TRANS" "$2" "${3:-300000}" "${4:-300000}"
}
crender() { cpay "$@" | "$RTC" statusline; }

printf '\n== the transcript TTL read ==\n'
fresh claude
TRANS="$W/transcript.jsonl"
printf '%s\n' '{"message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5,"cache_creation":{"ephemeral_5m_input_tokens":100,"ephemeral_1h_input_tokens":0}}}}' > "$TRANS"
printf '%s\n' '{"message":{"id":"m2","usage":{"input_tokens":10,"output_tokens":5,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":9000}}}}' >> "$TRANS"
crender p1 10.00 >/dev/null
is 'the 1-hour TTL is read off the transcript' 3600 "$(cstate 10)"

printf '\n== money ==\n'
is 'the first sighting is adopted, not announced' 10.00 "$(cstate 1)"
crender p2 12.50 >/dev/null
near 'a bump lands whole' 12.500000 "$(cstate 1)"
sample=$(tail -1 "$XDG_RUNTIME_DIR/rtc-$CSESS.turns" 2>/dev/null)
near 'and teaches the estimate $2.50 per 300k of context' \
  "$(awk 'BEGIN { printf "%.6f", 2.5 / 0.3 }')" "${sample:-0}" 0.0005
out=$(crender p3 13.00)
case "$out" in *'[~$'*) ok 'the estimate renders' ;; *) bad 'the estimate renders' '[~$' "$out" ;; esac
case "$out" in *'$13.00'*) ok 'the total renders' ;; *) bad 'the total renders' '$13.00' "$out" ;; esac

printf '\n== the band hook ==\n'
# 300k of a 1M window is band 3 at the default 10% bands.
msg=$(printf '{"session_id":"%s"}' "$CSESS" | "$RTC" hook)
case "$msg" in *systemMessage*30%*) ok 'the hook announces the band it crossed' ;;
                *) bad 'the hook announces the band it crossed' 'systemMessage … 30%' "$msg" ;; esac
msg=$(printf '{"session_id":"%s"}' "$CSESS" | "$RTC" hook)
is 'and says it once' '' "$msg"

printf '\n== the halt marker ==\n'
HALT="$XDG_RUNTIME_DIR/rtc-$CSESS.halt"
printf '{"session_id":"%s"}' "$CSESS" | RTC_RING=on_halt "$RTC" halt
if [ -e "$HALT" ]; then ok 'Stop leaves a marker for the next render'
else bad 'Stop leaves a marker for the next render' 'marker' 'none'; fi
rm -f "$HALT"
printf '{"session_id":"%s"}' "$CSESS" | RTC_RING=immediate "$RTC" halt
if [ -e "$HALT" ]; then bad 'and leaves nothing behind in the other modes' 'no marker' 'a marker'
else ok 'and leaves nothing behind in the other modes'; fi

printf '\n== doctor ==\n'
# doctor reports on what it finds wired, so give it a settings.json
# of its own rather than whatever this machine happens to have.
export CLAUDE_CONFIG_DIR="$W/claudeconf"; mkdir -p "$CLAUDE_CONFIG_DIR"
printf '{"statusLine":{"type":"command","command":"/usr/bin/true"}}' > "$CLAUDE_CONFIG_DIR/settings.json"
d=$("$RTC" doctor 2>&1); rc=$?
is 'doctor exits 0 so it can sit in an && chain' 0 "$rc"
case "$d" in *'live data'*) ok 'doctor reaches the end of its report' ;;
             *) bad 'doctor reaches the end of its report' 'live data' "$(printf '%s' "$d" | tail -3)" ;; esac
case "$d" in *'subagent spend is already inside'*) ok 'and answers the subagent question' ;;
             *) bad 'and answers the subagent question' 'the claude line' 'missing' ;; esac

printf '\n== setup and uninstall ==\n'
"$RTC" setup >/dev/null 2>&1
got=$(jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json")
is 'setup claims the statusLine slot' "$(readlink -f "$RTC")" "$got"
is 'and chains what was there' 'RTC_CHAIN=/usr/bin/true' \
  "$(grep '^RTC_CHAIN=' "$XDG_CONFIG_HOME/realtokencost/config" 2>/dev/null)"
"$RTC" uninstall >/dev/null 2>&1
is 'uninstall hands the slot back' '/usr/bin/true' \
  "$(jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json")"

report
