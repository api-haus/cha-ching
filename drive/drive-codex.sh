#!/usr/bin/env bash
# The codex side: the rollout tailer, adoption, per-row pricing across a
# mid-session model switch, the plain render, the band, the ring at Stop, and a
# setup/uninstall round trip on hooks.json.
set -u
. "$(dirname "$0")/lib.sh"

fresh codex
mkdir -p "$W/codex"
XSESS=xs
ROLL="$W/rollout.jsonl"
COUNTED="$W/counted.jsonl"
: > "$ROLL"; : > "$COUNTED"
COUNT=0

export RTC_PRICE_deepseek_v4_pro="1 0.1 1 4"
export RTC_PRICE_gpt_5_4="2 0.2 2.5 10"

xstate() { cut -d' ' -f"$1" < "$XDG_RUNTIME_DIR/rtc-codex-$XSESS.state" 2>/dev/null; }
xcost()  { xstate 1; }

xpay() {                        # xpay <event> [model] [turn_id]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","model":"%s","turn_id":"%s","permission_mode":"bypassPermissions"}' \
    "$XSESS" "$ROLL" "$W" "$1" "${2:-deepseek-v4-pro}" "${3:-t1}"
}
xrun() { xpay "$@" | "$RTC" codex; }

turnctx() {                     # turnctx <model>
  local line
  line=$(printf '{"timestamp":"x","ordinal":0,"type":"turn_context","payload":{"model":"%s","cwd":"/tmp"}}' "$1")
  printf '%s\n' "$line" >> "$ROLL"
  [ "$COUNT" = 1 ] && printf '%s\n' "$line" >> "$COUNTED"
  return 0
}

# input_tokens carries the cached and the newly written halves inside it, the
# way codex reports it, so the drive states the totals and lets the script work
# the plain-input term out for itself.
tok() {                         # tok <input_total> <cached> <cwrite> <out> [window]
  local line
  line=$(printf '{"timestamp":"x","ordinal":0,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":0},"last_token_usage":{"input_tokens":%s,"cached_input_tokens":%s,"cache_write_input_tokens":%s,"output_tokens":%s,"reasoning_output_tokens":0,"total_tokens":%s},"model_context_window":%s}},"rate_limits":null}' \
    "$1" "$2" "$3" "$4" "$(( $1 + $4 ))" "${5:-400000}")
  printf '%s\n' "$line" >> "$ROLL"
  [ "$COUNT" = 1 ] && printf '%s\n' "$line" >> "$COUNTED"
  return 0
}

# The bill, arrived at a second time: straight off the rows, by a different awk,
# carrying the model forward the way the rollout does.
xsum() {                        # xsum <alias=in,cread,cwrite,out> ...
  local rates="" a
  for a in "$@"; do rates="$rates$a"$'\n'; done
  jq -r 'if .type == "turn_context" then ["T", (.payload.model // "")] | @tsv
         elif .type == "event_msg" and .payload.type == "token_count" then
           (.payload.info.last_token_usage) as $u
           | ["U", ($u.input_tokens - $u.cached_input_tokens - $u.cache_write_input_tokens),
              $u.cached_input_tokens, $u.cache_write_input_tokens, $u.output_tokens] | @tsv
         else empty end' "$COUNTED" |
    awk -F'\t' -v rates="$rates" -v m0="$MODEL0" '
      BEGIN { m = m0
              n = split(rates, L, "\n")
              for (i = 1; i <= n; i++) if (L[i] != "") {
                split(L[i], kv, "="); split(kv[2], r, ",")
                ri[kv[1]] = r[1]; rcr[kv[1]] = r[2]; rcw[kv[1]] = r[3]; ro[kv[1]] = r[4] } }
      $1 == "T" { if ($2 != "") m = $2; next }
      $1 == "U" { if (!(m in ri)) next
                  d += ($2*ri[m] + $3*rcr[m] + $4*rcw[m] + $5*ro[m]) / 1000000 }
      END { printf "%.6f", d }'
}
MODEL0=deepseek-v4-pro

printf '\n== adoption ==\n'
turnctx deepseek-v4-pro
tok 20000 0 0 200
xrun SessionStart >/dev/null
near 'a rollout seen for the first time is adopted, never announced' 0 "$(xcost)"
is 'and its context is picked up all the same' '20200 400000' \
  "$(cat "$XDG_RUNTIME_DIR/rtc-codex-$XSESS.ctx" 2>/dev/null)"
is 'and the model it names is remembered' 'deepseek-v4-pro' \
  "$(cat "$XDG_RUNTIME_DIR/rtc-codex-$XSESS.model" 2>/dev/null)"

printf '\n== money ==\n'
COUNT=1
tok 40000 20000 0 300
out=$(xrun UserPromptSubmit deepseek-v4-pro t2)
# 20000 plain + 20000 cached + 300 out = 0.02 + 0.002 + 0.0012
near 'a request past the offset is priced from its own row' \
  "$(xsum 'deepseek-v4-pro=1,0.1,1,4')" "$(xcost)"
case "$out" in *systemMessage*) ok 'and the submit event renders a segment' ;;
  *) bad 'and the submit event renders a segment' 'systemMessage' "$out" ;; esac
case "$out" in *'$0.0'*|*'$0.02'*) ok 'carrying the running total' ;;
  *) bad 'carrying the running total' 'a dollar figure' "$out" ;; esac

printf '\n== the segment codex can actually show ==\n'
msg=$(printf '%s' "$out" | jq -r '.systemMessage')
case "$msg" in *$'\033'*) bad 'no escape survives into a codex systemMessage' 'plain text' 'ANSI' ;;
  *) ok 'no escape survives into a codex systemMessage' ;; esac
case "$msg" in *'█'*) ok 'the gauge is still drawn' ;;
  *) bad 'the gauge is still drawn' 'a bar' "$msg" ;; esac

printf '\n== a model switched mid-session ==\n'
# Both models bill inside one chunk, so a total that came out right by pricing
# every row at the session's model would have to be wrong here.
turnctx deepseek-v4-pro
tok 8000 0 0 50
turnctx gpt-5.4
tok 10000 0 5000 100
xrun Stop gpt-5.4 t2 >/dev/null
near 'each row is priced by the model its own turn_context names' \
  "$(xsum 'deepseek-v4-pro=1,0.1,1,4' 'gpt-5.4=2,0.2,2.5,10')" "$(xcost)"
is 'and the session remembers the one now running' 'gpt-5.4' \
  "$(cat "$XDG_RUNTIME_DIR/rtc-codex-$XSESS.model" 2>/dev/null)"

printf '\n== a half-written row ==\n'
before=$(xcost)
printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token' >> "$ROLL"
xrun UserPromptSubmit gpt-5.4 t3 >/dev/null
is 'a partial last line is left for the next event' "$before" "$(xcost)"
printf '_usage":{"input_tokens":1000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0,"total_tokens":1000},"model_context_window":400000}}}\n' >> "$ROLL"
printf '{"timestamp":"x","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0,"total_tokens":1000},"model_context_window":400000}},"rate_limits":null}\n' >> "$COUNTED"
xrun UserPromptSubmit gpt-5.4 t3 >/dev/null
near '  and counted once it is whole' \
  "$(xsum 'deepseek-v4-pro=1,0.1,1,4' 'gpt-5.4=2,0.2,2.5,10')" "$(xcost)"

printf '\n== a rotated rollout ==\n'
before=$(xcost)
turnctx gpt-5.4
tok 500 0 0 0
: > "$ROLL"
turnctx gpt-5.4
tok 900000 0 0 0 1000000
msg=$(xrun UserPromptSubmit gpt-5.4 t4 | jq -r '.systemMessage')
is 'a shorter rollout is adopted, never recounted' "$before" "$(xcost)"

printf '\n== the band ==\n'
case "$msg" in *'context 90% used'*) ok 'a crossed band rides along on the segment' ;;
  *) bad 'a crossed band rides along on the segment' 'context 90% used' "$msg" ;; esac
msg=$(xrun UserPromptSubmit gpt-5.4 t6 | jq -r '.systemMessage')
case "$msg" in *'context 90% used'*) bad '  and says it once' 'no band' "$msg" ;;
  *) ok '  and says it once' ;; esac

printf '\n== the ring sounds at Stop, with the money already in ==\n'
SESS2=xr
: > "$W/roll2.jsonl"
: > "$RTC_RING_LOG"
p2() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","model":"deepseek-v4-pro","turn_id":"z1"}' \
  "$SESS2" "$W/roll2.jsonl" "$W" "$1"; }
printf '{"timestamp":"x","type":"turn_context","payload":{"model":"deepseek-v4-pro"}}\n' > "$W/roll2.jsonl"
p2 SessionStart | RTC_MUTE=0 "$RTC" codex >/dev/null
printf '{"timestamp":"x","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{},"last_token_usage":{"input_tokens":2000000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0,"total_tokens":2000000},"model_context_window":400000}},"rate_limits":null}\n' >> "$W/roll2.jsonl"
p2 Stop | RTC_MUTE=0 "$RTC" codex >/dev/null
is 'Stop rings on the spot rather than leaving a marker' 1 "$(rings)"
if [ -e "$XDG_RUNTIME_DIR/rtc-codex-$SESS2.halt" ]
then bad '  and leaves no marker behind' 'no marker' 'a marker'
else ok '  and leaves no marker behind'; fi

SESS2=xh
: > "$W/roll3.jsonl"
: > "$RTC_RING_LOG"
printf '{"timestamp":"x","type":"turn_context","payload":{"model":"deepseek-v4-pro"}}\n' > "$W/roll3.jsonl"
p3() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","model":"deepseek-v4-pro","turn_id":"h1"}' \
  "$SESS2" "$W/roll3.jsonl" "$W" "$1"; }
p3 SessionStart | RTC_MUTE=0 RTC_RING=on_halt "$RTC" codex >/dev/null
printf '{"timestamp":"x","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{},"last_token_usage":{"input_tokens":2000000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0,"total_tokens":2000000},"model_context_window":400000}},"rate_limits":null}\n' >> "$W/roll3.jsonl"
p3 UserPromptSubmit | RTC_MUTE=0 RTC_RING=on_halt "$RTC" codex >/dev/null
is 'on_halt stays quiet while the turn is still running' 0 "$(rings)"
p3 Stop | RTC_MUTE=0 RTC_RING=on_halt "$RTC" codex >/dev/null
is '  and speaks when it hands back' 1 "$(rings)"

printf '\n== an event nobody asked to render ==\n'
is 'PostToolUse is silent unless RTC_CODEX_RENDER says otherwise' '' \
  "$(xrun PostToolUse gpt-5.4 t7)"
out=$(RTC_CODEX_RENDER=submit,tool,stop xpay PostToolUse gpt-5.4 t7 | RTC_CODEX_RENDER=submit,tool,stop "$RTC" codex)
case "$out" in *systemMessage*) ok '  and renders when it does' ;;
  *) bad '  and renders when it does' 'systemMessage' "$out" ;; esac

printf '\n== a provider that charges by the clock ==\n'
# Nothing fakes the clock: the windows are built around the hour it is now, one
# containing it and one not. See AGENTS.md for why a rate can have two halves.
PSESS=xp
PROLL="$W/roll-peak.jsonl"
HOUR=$(date -u +%H); HOUR=$((10#$HOUR))
IN="$HOUR-$(( (HOUR + 1) % 24 ))"
OUTW="$(( (HOUR + 2) % 24 ))-$(( (HOUR + 3) % 24 ))"
clocked() {                     # clocked <peak-windows> [rates] -> total after one 1M-token row
  rm -f "$XDG_RUNTIME_DIR/rtc-codex-$PSESS."*
  printf '{"timestamp":"x","type":"turn_context","payload":{"model":"clocked"}}\n' > "$PROLL"
  local pay rates=${2:-"10 1 0 100 5 0.5 0 50"}
  pay() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","model":"clocked","turn_id":"p1"}' \
    "$PSESS" "$PROLL" "$W" "$1"; }
  pay SessionStart | RTC_PRICE_clocked="$rates" RTC_PEAK_clocked="$1" "$RTC" codex >/dev/null
  printf '{"timestamp":"x","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{},"last_token_usage":{"input_tokens":1000000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0,"total_tokens":1000000},"model_context_window":400000}},"rate_limits":null}\n' >> "$PROLL"
  pay Stop | RTC_PRICE_clocked="$rates" RTC_PEAK_clocked="$1" "$RTC" codex >/dev/null
  cut -d' ' -f1 < "$XDG_RUNTIME_DIR/rtc-codex-$PSESS.state"
}
near 'inside a peak window the first four rates apply' 10.000000 "$(clocked "$IN")"
near 'outside every peak window the second four do' 5.000000 "$(clocked "$OUTW")"
near 'and four rates alone still mean one price at every hour' 10.000000 \
  "$(clocked "$OUTW" "10 1 0 100")"
# Two windows, because a wrapping one containing this hour only exists away
# from midnight and a fixed 23-1 only wraps onto it. Between them every hour
# puts the wrap branch under an assertion.
near 'a window running past midnight is one window, not none' 10.000000 \
  "$(clocked "$HOUR-$(( (HOUR + 23) % 24 ))")"
case "$HOUR" in 0|23) midnight=10.000000 ;; *) midnight=5.000000 ;; esac
near '  and the hours it does not reach stay off-peak' "$midnight" "$(clocked '23-1')"

printf '\n== money smaller than a cent ==\n'
sub=$(clocked "$OUTW" "0.004 0 0 0" >/dev/null; \
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","model":"clocked","turn_id":"p2"}' \
    "$PSESS" "$PROLL" "$W" | RTC_PRICE_clocked="0.004 0 0 0" "$RTC" codex | jq -r '.systemMessage')
if printf '%s' "$sub" | grep -qE ' \$0\.0[0-9]{3}'; then ok 'a sub-cent total keeps four decimals instead of reading zero'
else bad 'a sub-cent total keeps four decimals instead of reading zero' ' $0.0xxx' "$sub"; fi
if printf '%s' "$sub" | grep -qE '~\$0\.0[0-9]{3}'; then ok '  and so does the estimate beside it'
else bad '  and so does the estimate beside it' '~$0.0xxx' "$sub"; fi

printf '\n== a custom provider is priced as its own ==\n'
cat > "$W/codex/config.toml" <<'EOF'
model = "deepseek-v4-pro"
model_provider = "deepseek"
[model_providers.deepseek]
base_url = "https://api.deepseek.com/"
EOF
mkdir -p "$W/fake"
cat > "$W/fake/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"deepseek":{"models":{
   "deepseek-v4-pro":{"cost":{"input":0.435,"output":0.87,"cache_read":0.003625}}}},
 "cortecs":{"models":{
   "deepseek-v4-pro":{"cost":{"input":1.73,"output":3.46,"cache_read":0.432}}}}}
JSON
EOF
chmod +x "$W/fake/curl"
out=$(PATH="$W/fake:$PATH" "$RTC" rates 2>&1)
is 'the model codex is configured with is priced by its own provider' '0.435 0.003625 0.435 0.87' \
  "$(cut -d' ' -f1-4 < "$XDG_CACHE_HOME/realtokencost/price-deepseek-v4-pro" 2>/dev/null)"
case "$out" in *cortecs*) bad '  and not by a reseller carrying the same id' 'deepseek' "$out" ;;
  *) ok '  and not by a reseller carrying the same id' ;; esac

printf '\n== hooks.json ==\n'
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}\n' > "$W/codex/hooks.json"
PATH="$W/fake:$PATH" "$RTC" setup >/dev/null 2>&1
is 'setup wires the events it renders on' 'Stop UserPromptSubmit' \
  "$(jq -r '[.hooks | to_entries[] | select([.value[].hooks[].command] | map(test("rtc\"? codex")) | any) | .key] | sort | join(" ")' "$W/codex/hooks.json")"
is '  and leaves the hook that was already there' '/usr/bin/true' \
  "$(jq -r '[.hooks.Stop[].hooks[].command] | map(select(test("rtc") | not))[0] // "gone"' "$W/codex/hooks.json")"
PATH="$W/fake:$PATH" "$RTC" setup >/dev/null 2>&1
is '  running it twice leaves one hook per event, not two' 2 \
  "$(jq -r '[.hooks | to_entries[] | .value[].hooks[].command | select(test("rtc\"? codex"))] | length' "$W/codex/hooks.json")"
"$RTC" uninstall >/dev/null 2>&1
is 'uninstall takes only ours out' '/usr/bin/true' \
  "$(jq -r '[.hooks.Stop[].hooks[].command] | join(",")' "$W/codex/hooks.json")"

printf '\n== doctor ==\n'
d=$("$RTC" doctor 2>&1)
case "$d" in *'no status line command slot'*) ok 'doctor says why there is no status line' ;;
  *) bad 'doctor says why there is no status line' 'the codex line' 'missing' ;; esac
case "$d" in *'codex trust'*) ok 'and names the trust step codex needs' ;;
  *) bad 'and names the trust step codex needs' 'codex trust' 'missing' ;; esac

report
