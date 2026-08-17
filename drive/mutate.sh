#!/usr/bin/env bash
# Break one load-bearing line at a time and check that a drive notices.
#
# A drive that passes proves nothing on its own — this repo shipped an
# assertion that compared two literals and passed against every broken script
# it was ever run on. So the drives are themselves driven: each mutant below is
# a plausible way for the money to go wrong, and every one must turn some
# assertion red. A MISS is a hole in the suite, not a bug in the script.
#
# Each mutant is a call rather than a row in a table, because the lines being
# quoted are shell and any separator you pick turns up inside one of them —
# `||` ate the first version of this file. The line is matched whole and
# literally, so a mutant that goes stale says so instead of quietly passing.
set -u
cd "$(dirname "$0")"
REPO=$(cd .. && pwd)
OUT=${TMPDIR:-/tmp}/rtc-drive/mutant
mkdir -p "$OUT/bin"
ln -sfn "$REPO/share" "$OUT/share"
caught=0; missed=0

# mutant <name> <drive> <line> <replacement> [tries]
#
# `tries` is for a mutant that opens a race rather than a certainty. Deleting
# the ring lock does not make ten sessions lose a ring, it makes them lose one
# sometimes — three runs in eight under bash 3.2 in a container, and rarer than
# that on a fast native shell, where a single run of the drive passes a script
# with no mutex in it at all. Repetition is what the drive is short of there,
# and pretending otherwise by dropping the mutant would hide a real limit of
# the suite.
mutant() {
  local name=$1 drive=$2 old=$3 new=$4 tries=${5:-1} n=0 out first
  if ! old="$old" new="$new" awk '
        BEGIN { o = ENVIRON["old"]; n = ENVIRON["new"] }
        !done && $0 == o { print n; done = 1; next }
        { print }
        END { exit done ? 0 : 1 }' "$REPO/bin/rtc" > "$OUT/bin/rtc"; then
    printf '  ??   %s\n       that line is not in bin/rtc any more — the mutant is stale\n' "$name"
    missed=$((missed + 1)); return
  fi
  chmod +x "$OUT/bin/rtc"
  while [ "$n" -lt "$tries" ]; do
    n=$((n + 1))
    out=$(RTC="$OUT/bin/rtc" BASE="${TMPDIR:-/tmp}/rtc-drive/mut-$drive-$n" bash "./$drive.sh" 2>&1)
    first=$(printf '%s\n' "$out" | grep -m1 '^  FAIL' | sed 's/^  FAIL *//')
    [ -n "$first" ] && break
  done
  if [ -n "$first" ]; then
    caught=$((caught + 1))
    printf '  ok   %s\n       %s catches it%s: %s\n' "$name" "$drive" \
      "$([ "$tries" -gt 1 ] && printf ' on run %s of %s' "$n" "$tries")" "$first"
  else
    missed=$((missed + 1))
    printf '  MISS %s\n       %s passes a script with this broken%s\n' "$name" "$drive" \
      "$([ "$tries" -gt 1 ] && printf ', %s times over' "$tries")"
  fi
}

mutant 'halt marks in every mode' drive-claude \
  '  [ "$RING" = on_halt ] || exit 0' \
  '  :'

mutant 'a rebuild row is filed as an ordinary turn' drive-kimi \
  '  [ "${cw:-0}" -gt "${cr:-0}" ] && bucket=rebuilds' \
  '  :'

mutant 'a wire seen for the first time is always adopted' drive-kimi \
  '      if [ "$adopt" = 1 ]; then off=$size; else off=0; fi' \
  '      off=$size'

mutant 'the estimate is taught the total, not the main bump' drive-kimi \
  '      record_sample "$mainbump" "$used" "$cwrite" "$cread" "$tag-${session:-nosession}" "$ratefile"' \
  '      record_sample "$bump" "$used" "$cwrite" "$cread" "$tag-${session:-nosession}" "$ratefile"'

mutant 'a shorter wire is recounted instead of adopted' drive-kimi \
  '    elif [ "$size" -lt "$off" ]; then' \
  '    elif false; then'

mutant 'every row is priced by the session model' drive-real \
  '            price_for "${m//[^A-Za-z0-9._-]/_}" &&' \
  '            price_for "${modelid:-unknown}" &&'

mutant 'the ring lock is never taken' drive-concurrent \
  '      if [ "$need" = 1 ] && ring_lock "$gring.lock" "$now"; then' \
  '      if [ "$need" = 1 ]; then' 8

mutant 'a blank lock stamp means the holder died' drive-ring \
  '    case "${held:-}" in '\'''\''|*[!0-9.]*) held="" ;; esac' \
  '    case "${held:-}" in '\'''\''|*[!0-9.]*) held=0 ;; esac'

mutant 'a subagent wire is never tailed at all' drive-real \
  '  kimi_subagents "${wire%/main/wire.jsonl}" "$adopt"' \
  '  :'

mutant 'a resumed rollout is priced from byte 0' drive-codex \
  '  last_call=0; ttl=0; ring_acc=0; woffset=-1; sacc=0' \
  '  last_call=0; ttl=0; ring_acc=0; woffset=0; sacc=0'

mutant 'codex is sent a segment full of escapes it will drop' drive-codex \
  '    if (plain != "") { RESET = ""; DIM = "" }' \
  '    if (0) { RESET = ""; DIM = "" }'

mutant 'a codex row is priced by the session model, not its own' drive-codex \
  '               price_for "${a//[^A-Za-z0-9._-]/_}" &&' \
  '               price_for "${model//[^A-Za-z0-9._-]/_}" &&'

mutant 'the cached half is billed twice, as plain input as well' drive-codex \
  '          | ["U", (($u.input_tokens // 0) - ($u.cached_input_tokens // 0)' \
  '          | ["U", (($u.input_tokens // 0) - (0 * ($u.cached_input_tokens // 0))'

mutant 'a codex turn ending is not a turn handing back' drive-codex \
  '    Stop)             halted=1; case ",$CODEX_RENDER," in *,stop,*) show=1 ;; esac ;;' \
  '    Stop)             halted=0; case ",$CODEX_RENDER," in *,stop,*) show=1 ;; esac ;;'

mutant 'setup adds a second codex hook beside the first' drive-codex \
  '      .hooks = ((.hooks // {}) | map_values(map(select(($CODEX_MINE) | not))))' \
  '      .hooks = (.hooks // {})'

mutant 'a two-tier rate is always billed at its peak half' drive-codex \
  '      v=${v#* * * * }; PRICE_SRC="$PRICE_SRC off-peak"' \
  '      v=${v% * * * *}; PRICE_SRC="$PRICE_SRC off-peak"'

mutant 'a peak window running past midnight matches nothing' drive-codex \
  '      { [ "$h" -ge "$from" ] || [ "$h" -lt "$to" ]; } && return 0' \
  '      [ "$h" -ge "$from" ] && [ "$h" -lt "$to" ] && return 0'

mutant 'a sub-cent total is rounded away to $0.00' drive-codex \
  '  function money(v) { return (v > 0 && v < 0.01) ? sprintf("%.4f", v) : sprintf("%.2f", v) }' \
  '  function money(v) { return sprintf("%.2f", v) }'

mutant 'a sub-cent estimate is rounded away to $0.00' drive-codex \
  '    function money(v) { return (v > 0 && v < 0.01) ? sprintf("%.4f", v) : sprintf("%.2f", v) }' \
  '    function money(v) { return sprintf("%.2f", v) }'

mutant 'a non-numeric RTC_VOLUME reaches the player unguarded' drive-ring \
  '  case "$v" in '\'''\''|*[!0-9.]*) v=0.8 ;; esac' \
  '  :'

printf '\n%s caught, %s missed\n' "$caught" "$missed"
[ "$missed" = 0 ]
