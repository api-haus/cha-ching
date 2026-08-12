#!/usr/bin/env bash
# Real wires, not fabricated ones. Two runs: a real multi-subagent session
# replayed from byte 0, and the same session with one subagent's wire replaced
# by a real wire from a session that ran a different model — real rows, real
# aliases, real token counts, in the topology nothing on this machine has
# happened to produce on its own.
#
# Both sessions are found on this machine rather than named, so this keeps
# working when today's sessions are gone. With no Kimi history it skips.
set -u
. "$(dirname "$0")/lib.sh"

SRC=${SRC:-$(real_session)}
[ -n "${SRC:-}" ] || { skip 'the real-wire drives' 'no Kimi session with subagent wires'; exit 0; }

MAIN=$(jq -r 'select(.type=="usage.record") | .model' "$SRC/agents/main/wire.jsonl" 2>/dev/null | sort -u | head -1)
[ -n "${MAIN:-}" ] || { skip 'the real-wire drives' 'that session has no usage rows'; exit 0; }

envname() { printf 'RTC_PRICE_%s' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_')"; }
RATE_MAIN='3 0.3 3 15'
RATE_OTHER='9 0.9 9 45'
export "$(envname "$MAIN")=$RATE_MAIN"

# Adopt, then wind every offset back to zero and let the whole history land as
# if it had arrived while rtc was watching.
rewind() {
  local st="$XDG_RUNTIME_DIR/rtc-kimi-$SESS.state" sb="$XDG_RUNTIME_DIR/rtc-kimi-$SESS.subs"
  awk '{ $1 = 0; $12 = 0; $13 = 0; print }' "$st" > "$st.new" && mv "$st.new" "$st"
  [ -r "$sb" ] && { awk '{ $2 = 0; print }' "$sb" > "$sb.new" && mv "$sb.new" "$sb"; }
}

plant() {                       # plant — a scratch copy of the real session
  rm -rf "$W/kimi/sessions/proj/$SESS"
  cp -r "$SRC" "$W/kimi/sessions/proj/$SESS"
  D="$W/kimi/sessions/proj/$SESS"
}

printf '\n== a real session, replayed from byte 0 ==\n'
fresh real
plant
printf '  %s usage rows across %s wires, model %s\n' \
  "$(($(cat "$D"/agents/*/wire.jsonl | grep -c '"type":"usage.record"')))" \
  "$(($(ls "$D"/agents/*/wire.jsonl | wc -l)))" "$MAIN"
render >/dev/null
is 'the whole history is adopted, not announced' 0 "$(cost)"
rewind
render >/dev/null
want=$(sumdir "$D" "$MAIN=${RATE_MAIN// /,}")
near 'replayed, the total agrees with a sum over every row' "$want" "$(cost)" 0.000002
sub=$(sacc)
if [ "$(awk -v a="$sub" 'BEGIN { print (a > 0) ? 1 : 0 }')" = 1 ]
then ok "and the subagents' share is a real number (\$$sub of \$$(cost))"
else bad "the subagents' share is a real number" '> 0' "$sub"; fi

OTHER=$(other_model_wire "$MAIN") || {
  skip 'the second-model drives' 'no session on this machine ran another model'
  report; exit $?
}
FCW=${OTHER%%$'\t'*}; ALT=${OTHER##*$'\t'}
export "$(envname "$ALT")=$RATE_OTHER"

printf '\n== the same session with a second real model on a subagent ==\n'
fresh mixed
plant
victim=$(ls -d "$D"/agents/agent-* | head -1)
cp "$FCW" "$victim/wire.jsonl"
printf '  %s now carries %s rows of %s\n' "${victim##*/}" \
  "$(($(grep -c '"type":"usage.record"' "$victim/wire.jsonl")))" "$ALT"
render >/dev/null
rewind
render >/dev/null
want=$(sumdir "$D" "$MAIN=${RATE_MAIN// /,}" "$ALT=${RATE_OTHER// /,}")
near 'each row is priced by the model that row names' "$want" "$(cost)" 0.000002
justmain=$(sumdir "$D" "$MAIN=${RATE_MAIN// /,}")

# The same run with the second model left unpriced must come up short by
# exactly that model's share, and by nothing else.
fresh unpriced
plant
cp "$FCW" "$(ls -d "$D"/agents/agent-* | head -1)/wire.jsonl"
unset "$(envname "$ALT")"
render >/dev/null
rewind
render >/dev/null
near 'a subagent model with no rate goes missing, and nothing else does' \
  "$justmain" "$(cost)" 0.000002
d=$("$RTC" doctor 2>&1)
case "$d" in *'NO RATE, its spend is missing from the total'*)
  ok 'and doctor names it rather than letting the total look complete' ;;
  *) bad 'and doctor names it' 'the NO RATE line' 'no such line' ;; esac

report
