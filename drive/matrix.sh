#!/usr/bin/env bash
# Every drive on every platform this project claims to support.
#
# macOS is supported deliberately and there is no macOS here, so it is built
# out of the two halves that actually differ. A macOS-shaped PATH — only the
# utilities macOS ships, with BSD-behaving stat and date, and no setsid and no
# tac, which are the two absences that have already cost this project a
# silently dead ring. And bash 3.2.57, which is still what /bin/bash is there,
# in a container. Each half found real bugs; run both before believing a
# platform claim.
#
#   ./drive/matrix.sh            everything available here
#   ./drive/matrix.sh native     this platform only, no shims, no container
set -u
cd "$(dirname "$0")"
only=${1:-all}
rc=0

printf '\n########## %s ##########\n' "$(uname -s), $(bash --version | head -1 | sed 's/GNU bash, version //;s/ .*//')"
BASE=${TMPDIR:-/tmp}/rtc-drive/native ./run-all.sh native || rc=1
[ "$only" = native ] && exit $rc

SHIM=${TMPDIR:-/tmp}/rtc-drive/macshim/bin
if ./mkshim.sh "$SHIM" >/dev/null; then
  printf '\n########## macOS-shaped userland (BSD stat and date, no setsid, no tac) ##########\n'
  env -i PATH="$SHIM" HOME="$HOME" TERM="${TERM:-dumb}" \
      KIMI_REAL_HOME="${KIMI_REAL_HOME:-$HOME/.kimi-code}" \
      BASE="${TMPDIR:-/tmp}/rtc-drive/mac" /bin/bash ./run-all.sh macos-shim || rc=1
fi

if command -v docker >/dev/null 2>&1 && docker version >/dev/null 2>&1; then
  printf '\n########## bash 3.2.57, the shell macOS still ships ##########\n'
  docker build -q -t rtc-bash32 - >/dev/null <<'EOF'
FROM bash:3.2
RUN apk add --no-cache jq coreutils findutils grep sed
EOF
  repo=$(cd .. && pwd)
  docker run --rm --user "$(id -u):$(id -g)" \
    -v "$repo:$repo:ro" -v "$HOME/.kimi-code:$HOME/.kimi-code:ro" \
    -v "${TMPDIR:-/tmp}/rtc-drive:${TMPDIR:-/tmp}/rtc-drive" \
    -e HOME="$HOME" -e "BASE=${TMPDIR:-/tmp}/rtc-drive/b32" \
    -w "$repo/drive" rtc-bash32 ./run-all.sh bash-3.2 || rc=1
else
  printf '\n  (no docker — bash 3.2 not exercised)\n'
fi

exit $rc
