#!/usr/bin/env bash
# Build a macOS-shaped PATH: only the utilities macOS actually ships, with
# BSD-behaving stand-ins for the ones whose flags differ from GNU. What is
# missing is as much of the point as what is present — macOS has no setsid and
# no tac, and the script must survive both.
set -eu
S=${1:?shim bin dir}
mkdir -p "$S"; rm -f "$S"/*
for c in awk sed grep cut tr wc head sort uniq find mktemp cp mv rm cat ls \
         sleep dirname basename readlink touch jq curl du chmod printf \
         bash sh env mkdir rmdir ln id seq kill tee xargs expr true false; do
  p=$(command -v "$c" 2>/dev/null) || continue
  ln -sf "$p" "$S/$c"
done

cat > "$S/date" <<'EOF'
#!/bin/bash
# BSD date has no %N. macOS reports the unknown conversion as a bare N.
a=(); for x in "$@"; do case "$x" in +*) x=${x//%N/N} ;; esac; a+=("$x"); done
exec /usr/bin/date "${a[@]}"
EOF

cat > "$S/stat" <<'EOF'
#!/bin/bash
# BSD stat: -f formats only; -c is an illegal option.
case "${1:-}" in
  -c) printf 'stat: illegal option -- c\n' >&2; exit 1 ;;
  -f) f=$2; shift 2
      case "$f" in
        '%z %N') exec /usr/bin/stat -c '%s %n' "$@" ;;
        '%z')    exec /usr/bin/stat -c '%s'    "$@" ;;
        '%m')    exec /usr/bin/stat -c '%Y'    "$@" ;;
        *) printf 'stat shim: unhandled format %s\n' "$f" >&2; exit 1 ;;
      esac ;;
esac
exec /usr/bin/stat "$@"
EOF

cat > "$S/tail" <<'EOF'
#!/bin/bash
# macOS tail has -r; GNU tail does not.
if [ "${1:-}" = "-r" ]; then shift; exec /usr/bin/tac "$@"; fi
exec /usr/bin/tail "$@"
EOF

cat > "$S/afplay" <<'EOF'
#!/bin/bash
# The macOS player. Records that it was reached, so a ring can be counted.
printf '%s %s\n' "$(/usr/bin/date +%s.%N)" "${1:-}" >> "${RTC_RING_LOG:-/dev/null}"
EOF

chmod +x "$S/date" "$S/stat" "$S/tail" "$S/afplay"
printf 'shim ready: %s\n' "$S"
