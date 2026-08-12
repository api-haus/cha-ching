#!/usr/bin/env bash
# `rtc rates` against a canned models.dev, with a subagent running a model that
# config.toml has never heard of — the case where the fetch has to find its
# roster somewhere other than the config.
set -u
. "$(dirname "$0")/lib.sh"

fresh rates
CACHE="$XDG_CACHE_HOME/realtokencost"

cat > "$W/kimi/config.toml" <<'EOF'
[models."kimi-code/k3"]
provider = "managed:kimi-code"
model = "k3"
EOF

# The session's own model, and three a subagent turned out to be running.
printf '%s\n%s\n' "$SDIR/agents/main/wire.jsonl" 'kimi-code/k3' \
  > "$XDG_RUNTIME_DIR/rtc-kimi-$SESS.wire"
cat > "$XDG_RUNTIME_DIR/rtc-kimi-$SESS.subs" <<'EOF'
agent-0 400 kimi-code/kimi-for-coding
agent-1 900 kimi-code/k2
agent-2 120 kimi-code/nobody-sells-this
EOF

mkdir -p "$W/fake"
cat > "$W/fake/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"moonshotai":{"models":{
   "k3":{"cost":{"input":3,"output":15,"cache_read":0.3,"cache_write":3}},
   "kimi-for-coding":{"cost":{"input":1,"output":5}},
   "kimi-k2":{"cost":{"input":0.6,"output":2.5,"cache_read":0.06,"cache_write":0.6}}}},
 "someproxy":{"models":{
   "k3":{"cost":{"input":99,"output":99,"cache_read":99,"cache_write":99}}}}}
JSON
EOF
chmod +x "$W/fake/curl"
export PATH="$W/fake:$PATH"

out=$("$RTC" rates 2>&1)
printf '%s\n' "$out" | sed 's/^/    | /'

printf '\n'
if [ -r "$CACHE/price-kimi-code_k3" ]; then ok 'the configured model is priced'
else bad 'the configured model is priced' 'price file' 'none'; fi
is '  from the first-party provider, not the proxy' '3 0.3 3 15' \
  "$(cut -d' ' -f1-4 < "$CACHE/price-kimi-code_k3" 2>/dev/null)"

if [ -r "$CACHE/price-kimi-code_kimi-for-coding" ]
then ok 'a subagent model no config.toml declares is priced too'
else bad 'a subagent model no config.toml declares is priced too' 'price file' 'none'; fi
is '  with the unpublished cache rates falling back to input' '1 1 1 5' \
  "$(cut -d' ' -f1-4 < "$CACHE/price-kimi-code_kimi-for-coding" 2>/dev/null)"

is '  and an alias models.dev carries under a kimi- prefix resolves' '0.6 0.06 0.6 2.5' \
  "$(cut -d' ' -f1-4 < "$CACHE/price-kimi-code_k2" 2>/dev/null)"

case "$out" in *'no models.dev match for "nobody-sells-this"'*)
  ok 'an unmatched model gets instructions, not an invented number' ;;
  *) bad 'an unmatched model gets instructions, not an invented number' \
        'the no-match line' "$out" ;; esac
if [ -e "$CACHE/price-kimi-code_nobody-sells-this" ]
then bad '  and no file' 'no price file' 'one was written'
else ok '  and no price file'; fi

# The same money, priced end to end: a render must now find the fetched rate.
printf '\n== the fetched rate reaches a render ==\n'
unset RTC_PRICE_kimi_code_k3 2>/dev/null || true
M="$SDIR/agents/main/wire.jsonl"; mkdir -p "$(dirname "$M")"; : > "$M"
A0="$SDIR/agents/agent-0/wire.jsonl"; mkdir -p "$(dirname "$A0")"; : > "$A0"
rm -f "$XDG_RUNTIME_DIR/rtc-kimi-$SESS."*
row "$M" 1 0 0 0
render >/dev/null
row "$M"  1000 1000 0 1000 'kimi-code/k3'
row "$A0" 1000 1000 0 1000 'kimi-code/kimi-for-coding'
render >/dev/null
# k3: 3000 + 300 + 15000 = 0.0183   fc: 1000 + 1000 + 5000 = 0.007
near 'both wires priced from the fetched cache' 0.025300 "$(cost)"
near '  and the subagent share is the fetched second rate' 0.007000 "$(sacc)"

report
