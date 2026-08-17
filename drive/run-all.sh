#!/usr/bin/env bash
# Every drive, on one platform. matrix.sh calls this once per platform with a
# name and an environment it has already arranged; run it directly to drive
# whatever platform you are standing on.
set -u
cd "$(dirname "$0")"
name=${1:?platform name}
rc=0
for d in drive-kimi drive-claude drive-codex drive-ring drive-rates drive-concurrent drive-real; do
  [ -r "./$d.sh" ] || continue
  out=$(bash "./$d.sh" 2>&1)
  line=$(printf '%s' "$out" | tail -1)
  case "$line" in
    *' 0 failed') printf '  %-18s %s\n' "$d" "$line" ;;
    *) rc=1; printf '  %-18s %s\n' "$d" "${line:-no verdict}"
       printf '%s\n' "$out" | grep -A2 '^  FAIL' | sed 's/^/      /' ;;
  esac
done
printf '  --- %s: %s\n' "$name" "$([ $rc = 0 ] && printf 'all green' || printf 'FAILURES')"
exit $rc
