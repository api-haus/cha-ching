#!/usr/bin/env bash
# The ear: the cooldown, and the mutex that keeps ten sessions from ringing at
# once. Both are driven off now_s(), so both are hostage to what `date` on the
# platform actually prints.
set -u
. "$(dirname "$0")/lib.sh"
export RTC_PRICE_kimi_code_k3='3 0.3 3 15'
export RTC_MUTE=0


printf '\n== now_s under this platform ==\n'
t=$(date +%s.%N)
printf '  date +%%s.%%N -> %s\n' "$t"
case "$t" in *[!0-9.]*) printf '  (not a number — every clock in the script reads this)\n' ;; esac

printf '\n== the cooldown ==\n'
fresh ring; export RTC_RING_SCOPE=global RTC_RING=immediate RTC_COOLDOWN=30
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
row "$M" 1 0 0 0; render >/dev/null            # adopt
row "$M" 100000 0 0 100000; render >/dev/null  # $1.80 — rings
is 'a bump over MIN rings once' 1 "$(rings)"
row "$M" 100000 0 0 100000; render >/dev/null  # inside a 30s cooldown
is 'a second bump inside the cooldown stays quiet' 1 "$(rings)"

printf '\n== the mutex ==\n'
fresh lock; export RTC_RING_SCOPE=global RTC_RING=immediate RTC_COOLDOWN=0
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
row "$M" 1 0 0 0; render >/dev/null
# Another session is holding the lock right now, and has held it for well under
# the five seconds that mean it died holding it.
LOCK="$XDG_RUNTIME_DIR/rtc-global-${UID:-0}.ring.lock"
# What a holder writes is now_s(), which is a number on every platform.
printf '%s\n' "$(date +%s)" > "$LOCK"
row "$M" 100000 0 0 100000
render >/dev/null
if [ -e "$LOCK" ]; then ok 'a held lock is left alone'
else bad 'a held lock is left alone' 'lock still held' 'lock was taken from its holder'; fi
is '  and the ring defers rather than fires' 0 "$(rings)"
carried=$(field 1 11)
if [ "$(awk -v a="${carried:-0}" 'BEGIN { print (a > 0) ? 1 : 0 }')" = 1 ]
then ok '  and the money is carried, not dropped'
else bad '  and the money is carried, not dropped' '> 0' "$carried"; fi
rm -f "$LOCK"
render >/dev/null
is '  and lands on the next render' 1 "$(rings)"

# Taking the lock is an O_EXCL open followed by a write, so a contender can
# land between the two and read a file that exists and says nothing yet. An
# empty stamp is a holder a microsecond old, and reading it as epoch zero put
# two sessions in the critical section at once — measured as a lost write and
# a missing ring, once in a while, under ten-way contention.
# Reclaiming it after the whole spin is right — a stamp still unreadable 200ms
# later is a corpse. Entering the section on the first attempt is not.
before=$(rings)
: > "$LOCK"
row "$M" 100000 0 0 100000
render >/dev/null
is 'a lock caught between its open and its write is not entered' "$before" "$(rings)"
carried=$(field 1 11)
if [ "$(awk -v a="${carried:-0}" 'BEGIN { print (a > 0) ? 1 : 0 }')" = 1 ]
then ok '  the money waits instead'
else bad '  the money waits instead' '> 0' "$carried"; fi
rm -f "$LOCK"
render >/dev/null

printf '\n== the detached rates refresh ==\n'
fresh refresh; export RTC_RATES_REFRESH=1 RTC_RING_SCOPE=session
unset RTC_PRICE_kimi_code_k3          # fall through to the bundled seed
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
row "$M" 1 0 0 0
err=$(render 2>&1 >/dev/null)
is 'a seed-priced render spawns its refresh without complaining' '' "$err"
if [ -e "$XDG_CACHE_HOME/realtokencost/.rates-when" ]
then ok '  and marks the attempt so a fleet spawns one fetch'
else bad '  and marks the attempt so a fleet spawns one fetch' 'marker written' 'no marker'; fi
export RTC_PRICE_kimi_code_k3='3 0.3 3 15'

printf '\n== the volume flag, per player ==\n'
export RTC_RING_SCOPE=session RTC_RING=immediate RTC_COOLDOWN=0 RTC_MIN=0

# Each player takes loudness differently, so what should reach it is worked
# out here a second time rather than by asking play_sound. A private
# one-binary PATH per case runs every branch on every machine, including one
# with none of the four players actually installed and one — this native
# host — with all of them, where testing paplay only means pw-play must not
# be found either. The needed tools are resolved with command -v against the
# PATH fresh() already set up (real jq, real date, wherever they live) rather
# than borrowed from mkshim.sh, whose BSD date/stat/tail shims hardcode
# /usr/bin/date and break inside a container that keeps date at /bin/date.
one_player() {                  # one_player <name> — the only player on PATH
  rm -rf "$W/only"; mkdir -p "$W/only"
  local c p
  for c in awk sed grep cut tr wc head tail sort uniq find mktemp cp mv rm cat ls \
           sleep dirname basename readlink touch jq curl du chmod printf date stat \
           bash sh env mkdir rmdir ln id seq kill tee xargs expr true false; do
    p=$(command -v "$c" 2>/dev/null) || continue
    ln -sf "$p" "$W/only/$c"
  done
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${RTC_RING_LOG:-/dev/null}"\n' > "$W/only/$1"
  chmod +x "$W/only/$1"
  export PATH="$W/only"
}

vring() {                       # vring [RTC_VOLUME] — one wire bump, captured
  if [ -n "${1:-}" ]; then export RTC_VOLUME="$1"; else unset RTC_VOLUME; fi
  : > "$RTC_RING_LOG"
  row "$M" 100000 0 0 100000; render >/dev/null
  sleep 0.4
  tail -1 "$RTC_RING_LOG" 2>/dev/null
}

fresh vol-pw; one_player pw-play
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
row "$M" 1 0 0 0; render >/dev/null   # adopt
got=$(vring 0.3)
case "$got" in *'--volume=0.300'*) ok 'pw-play gets a linear fraction' ;;
  *) bad 'pw-play gets a linear fraction' '--volume=0.300' "$got" ;; esac

fresh vol-pa; one_player paplay
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
row "$M" 1 0 0 0; render >/dev/null   # adopt
got=$(vring 0.3)
case "$got" in *'--volume=19661'*) ok 'paplay gets an integer up to 65536' ;;
  *) bad 'paplay gets an integer up to 65536' '--volume=19661' "$got" ;; esac

fresh vol-al; one_player aplay
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
row "$M" 1 0 0 0; render >/dev/null   # adopt
got=$(vring 0.3)
case "$got" in *'--volume'*) bad 'aplay is given no gain flag it cannot use' 'no --volume' "$got" ;;
  *) ok 'aplay is given no gain flag it cannot use' ;; esac

fresh vol-af; one_player afplay
M="$SDIR/agents/main/wire.jsonl"; : > "$M"
row "$M" 1 0 0 0; render >/dev/null   # adopt
got=$(vring 0.3)
case "$got" in *'-v 0.300'*) ok 'afplay gets -v, the flag it actually ships' ;;
  *) bad 'afplay gets -v, the flag it actually ships' '-v 0.300' "$got" ;; esac
got=$(vring)
case "$got" in *'-v 0.800'*) ok 'and an unset RTC_VOLUME defaults to 0.8' ;;
  *) bad 'and an unset RTC_VOLUME defaults to 0.8' '-v 0.800' "$got" ;; esac
got=$(vring banana)
case "$got" in *'-v 0.800'*) ok 'a non-numeric RTC_VOLUME falls back to the default' ;;
  *) bad 'a non-numeric RTC_VOLUME falls back to the default' '-v 0.800' "$got" ;; esac
got=$(vring -2)
case "$got" in *'-v 0.800'*) ok 'a negative RTC_VOLUME falls back to the default too' ;;
  *) bad 'a negative RTC_VOLUME falls back to the default too' '-v 0.800' "$got" ;; esac
got=$(vring 4)
case "$got" in *'-v 1.000'*) ok 'RTC_VOLUME above 1 clamps to 1' ;;
  *) bad 'RTC_VOLUME above 1 clamps to 1' '-v 1.000' "$got" ;; esac

report
