# Shared helpers for the drives. Sourced, never run.
#
# Every drive builds its own world — scratch KIMI_CODE_HOME, scratch runtime,
# scratch cache and config — so a run can never teach the real model rate,
# touch the real shared ring, or leave state behind for a live session to read.
# Nothing here shares code with the script under test: the expected figures are
# computed a second time, from the rows, by a different awk.
export LC_ALL=C
_HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
RTC=${RTC:-$_HERE/../bin/rtc}
BASE=${BASE:-${TMPDIR:-/tmp}/rtc-drive}
_PATH0=$PATH
PASS=0; FAIL=0

fresh() {                       # fresh <name> — a clean world, exported
  W="$BASE/w-$1"
  rm -rf "$W"; mkdir -p "$W/run" "$W/cache" "$W/config" "$W/kimi/sessions/proj" "$W/player"
  export XDG_RUNTIME_DIR="$W/run" XDG_CACHE_HOME="$W/cache" \
         XDG_CONFIG_HOME="$W/config" KIMI_CODE_HOME="$W/kimi" \
         RTC_MUTE="${RTC_MUTE-1}" RTC_RATES_REFRESH="${RTC_RATES_REFRESH-0}" \
         RTC_RING_SCOPE="${RTC_RING_SCOPE-session}"

  # A player that records instead of playing, named after whichever one this
  # platform would have reached, so play_sound takes the same branch it takes
  # in earnest. Rings are counted off the log it writes.
  local p name=afplay
  for p in pw-play paplay aplay afplay; do
    command -v "$p" >/dev/null 2>&1 && { name=$p; break; }
  done
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$(date +%%s)" "${1:-}" >> "${RTC_RING_LOG:-/dev/null}"\n' \
    > "$W/player/$name"
  chmod +x "$W/player/$name"
  export PATH="$W/player:$_PATH0" RTC_RING_LOG="$W/rings"
  : > "$RTC_RING_LOG"

  SESS=${SESS:-session_t}
  SDIR="$W/kimi/sessions/proj/$SESS"
  mkdir -p "$SDIR/agents/main"
}

snap() {                        # snap [contextTokens]
  printf '{"model":"K3","cwd":"/tmp","gitBranch":null,"permissionMode":"manual","planMode":false,"contextUsage":0.05,"contextTokens":%s,"maxContextTokens":1048576,"sessionId":"%s","version":"0.34.0"}' \
    "${1:-55000}" "$SESS"
}

render() { snap "${1:-55000}" | "$RTC" statusline; }

row() {                         # row <wire> <io> <cread> <cwrite> <out> [model] [time]
  printf '{"type":"usage.record","model":"%s","usage":{"inputOther":%s,"output":%s,"inputCacheRead":%s,"inputCacheCreation":%s},"usageScope":"turn","time":%s}\n' \
    "${6:-kimi-code/k3}" "$2" "$5" "$3" "$4" "${7:-1}" >> "$1"
}

field() { cut -d' ' -f"$2" < "$XDG_RUNTIME_DIR/rtc-kimi-$SESS.state" 2>/dev/null; }
cost()  { field 1 1; }
sacc()  { field 1 13; }
# The player is detached on purpose, so a wedged audio server never stalls a
# render. Give it a beat to land before counting.
rings() { sleep 0.4; wc -l < "$RTC_RING_LOG" 2>/dev/null | tr -d ' '; }

# Price every usage.record row in every wire under a session directory, from
# the rows themselves. This is the figure rtc's running total is compared
# against, and it is arrived at by a different route.
sumdir() {                      # sumdir <session-dir> <alias=i,cr,cw,o> ...
  local d="$1"; shift
  local rates="" a
  for a in "$@"; do rates="$rates$a"$'\n'; done
  cat "$d"/agents/*/wire.jsonl 2>/dev/null |
    jq -r 'select(.type=="usage.record") |
      [.model, (.usage.inputOther//0), (.usage.inputCacheRead//0),
       (.usage.inputCacheCreation//0), (.usage.output//0)] | @tsv' |
    awk -F'\t' -v rates="$rates" '
      BEGIN { n = split(rates, L, "\n")
              for (i = 1; i <= n; i++) if (L[i] != "") {
                split(L[i], kv, "="); split(kv[2], r, ",")
                ri[kv[1]] = r[1]; rcr[kv[1]] = r[2]; rcw[kv[1]] = r[3]; ro[kv[1]] = r[4] } }
      { if (!($1 in ri)) next
        d += ($2*ri[$1] + $3*rcr[$1] + $4*rcw[$1] + $5*ro[$1]) / 1000000 }
      END { printf "%.6f", d }'
}

# A real session on this machine with the most subagent wires, and a real wire
# running some other model — the drives that want real rows find their own
# rather than naming a session that will be gone next month.
real_session() {
  local d best="" n most=0
  for d in "${KIMI_REAL_HOME:-$HOME/.kimi-code}"/sessions/*/session_*; do
    [ -d "$d/agents" ] || continue
    n=$(ls -d "$d"/agents/agent-* 2>/dev/null | wc -l); n=$((n))
    [ "$n" -gt "$most" ] && { most=$n; best=$d; }
  done
  [ -n "$best" ] && printf '%s' "$best"
}

other_model_wire() {            # a real main wire whose model is not <alias>
  local w m
  for w in "${KIMI_REAL_HOME:-$HOME/.kimi-code}"/sessions/*/session_*/agents/main/wire.jsonl; do
    [ -r "$w" ] || continue
    m=$(jq -r 'select(.type=="usage.record") | .model' "$w" 2>/dev/null | sort -u)
    case "$m" in ''|*$'\n'*|"$1") continue ;; esac
    printf '%s\t%s' "$w" "$m"; return 0
  done
  return 1
}

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     want: %s\n     got:  %s\n' "$1" "$2" "$3"; }
skip() { printf '  --   %s (skipped: %s)\n' "$1" "$2"; }
is()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }
near() {                        # near <label> <want> <got> [tolerance]
  local t=${4:-0.000001}
  if [ "$(awk -v a="$2" -v b="$3" -v t="$t" 'BEGIN { d=a-b; if (d<0) d=-d; print (d<=t)?1:0 }')" = 1 ]
  then ok "$1 ($3)"; else bad "$1" "$2" "$3"; fi
}
report() { printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"; [ "$FAIL" = 0 ]; }
