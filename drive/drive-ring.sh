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

report
