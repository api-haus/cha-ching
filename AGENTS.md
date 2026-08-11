# AGENTS.md

realtokencost (`rtc`) is a Claude Code plugin: a statusline segment plus a hook. It shows what
submitting the current context costs *before* you press enter, whether the prompt cache is still
alive to make that the cheap number, rings a cash register when money moves, and warns as the window
fills. `README.md` is written for users; this file is what you need to change the thing.

Everything below was verified against Claude Code 2.1.227 by reading the binary and live payloads.
Where a claim is checkable, the check is named. Re-verify rather than trust if a claim starts costing
you time — the CLI moves.

## The constraints that shape the design

Read these before proposing an architecture change. Each one has already been paid for.

**A plugin cannot register a statusline.** `statusLine` is a settings key with no plugin path — there
is no `pluginStatusLine` identifier in the binary. Hooks install themselves via `hooks/hooks.json`;
the statusline needs `rtc setup` to write `settings.json`. This asymmetry is why setup exists at all.

**Hook payloads carry neither cost nor context.** `cost.total_cost_usd` and `context_window` are
handed to the statusline and to nothing else. The request to expose context usage to hooks
([anthropics/claude-code#27969](https://github.com/anthropics/claude-code/issues/27969)) was closed as
a duplicate. So the statusline harvests to files under `$XDG_RUNTIME_DIR` and the hook reads them
there. That bridge is not a workaround to be cleaned up; it is the only path.

**Never ship a price table.** The CLI has one compiled in (`inputTokens:5, outputTokens:25,
promptCacheWriteTokens:6.25, promptCacheWrite1hTokens:10, promptCacheReadTokens:0.5` per million) and
it is exactly what goes stale. `rtc` measures instead: each request bump says this much money bought a
re-read of this much context. Validated against first principles on a live session — learned `$0.18`
where `332,258 × $0.50/M` gives `$0.17`. Keep it that way.

**`LC_ALL=C` at the top of the script is load-bearing.** Money and percentages are text all the way
through. Under a comma-decimal locale `awk` and `printf` disagree about what `9.76` means and the
arithmetic silently stops working. Found on a Ukrainian-locale shell.

**One API response writes several transcript records.** Text, thinking and each `tool_use` block get
their own record, and every one carries the same `usage` object. Any transcript analysis must
`group_by(.message.id)` first. Summing records inflated a measurement by roughly half before this was
caught.

**The version must bump for an update to reach an install.** Refreshing a marketplace does not
re-fetch a plugin whose version has not moved. A fix left at the same version sits unreachable; this
has already happened once.

## Layout

```
bin/rtc                      everything — one bash script, six subcommands
hooks/hooks.json             UserPromptSubmit -> rtc hook; Stop, Notification -> rtc halt
commands/setup.md            /realtokencost:setup
share/cash-register.wav      CC0, see share/ATTRIBUTION.md
.claude-plugin/plugin.json   plugin manifest
.claude-plugin/marketplace.json   single-plugin marketplace, source "./"
```

`rtc statusline` is what `statusLine.command` runs. `rtc hook`, `halt`, `setup`, `uninstall`,
`doctor` are the rest. `doctor` exists to answer "why is it quiet" without a debugging session —
extend it when you add a way for things to be quiet. Three ring modes are three such ways, which is
why each prints its own line there.

## Runtime state

Per session under `$XDG_RUNTIME_DIR` (falling back to `TMPDIR`), keyed by `session_id`:

| file | holds |
|---|---|
| `rtc-<id>.state` | ten space-separated fields, order below |
| `rtc-<id>.turns` | recent ordinary request ratios, `$` per million tokens of context |
| `rtc-<id>.rebuilds` | ratios from requests that rebuilt the cache — a different thing entirely |
| `rtc-<id>.ctx` | `used size`, the bridge the hook reads |
| `rtc-<id>.line` | cache key on line 1, rendered segment on line 2 |
| `rtc-<id>.band` | highest context band already announced |
| `rtc-<id>.halt` | the turn handed back; consumed by the next render |
| `rtc-<id>.nudged` | set once when told to run setup |

State field order, positional, read with one `read`:

```
cost pending ring_ts shown shown_ts prev_prompt turn_cost turn_ctx last_call ttl ring_acc
```

Adding a field means appending and widening the `read` — never reordering, and never widening one
without the other: `read` puts everything it has no variable left for into the last one, so a write
that outruns its `read` does not lose the new field, it corrupts the previous one. Old state files
are read by new binaries in the wild, and the missing trailing field comes back empty rather than
absent, so every new field needs a default after the `read`.

Across sessions, `$XDG_CACHE_HOME/realtokencost/rate-<model_id>` holds what a bare submit costs for
that model. It is a property of the model, not the session, so a new session inherits it and shows a
figure immediately instead of relearning a constant. Only ordinary requests teach it.

Also across sessions, under the default `RTC_RING_SCOPE=global`, the ear's state leaves the session
file for `$RUN/rtc-global-<uid>.ring`: when the last ring was, and what has not been announced yet.
The uid is in the name because `TMPDIR` stands in for `XDG_RUNTIME_DIR` where there is none and
`/tmp` is shared — a file owned by another user fails every write silently, which reads from the
inside exactly like a broken ring. In this scope `ring_acc` in the session file means something
narrower: money this session accepted but has not handed over yet, non-zero only between losing the
lock and winning it back.

## Things deliberately not done

Do not "fix" these. Each was tried or considered and rejected for a reason.

**Predicting what the turn will do.** An earlier version showed a range whose upper bound guessed how
many tool calls Claude would make. That is a property of the work, not of the context, and no history
predicts it — measured spread was 7.8× between a bare reply and a tool-heavy turn. Only the submit
cost is knowable before the request is sent, and only that is shown.

**Cost per keystroke.** The payload carries `prompt_id` but never the draft text. There is nothing to
estimate from.

**Showing the figure only while typing.** Needs a typing signal. Measured over 68 seconds across two
dozen live sessions, every render arrived on the `refreshInterval` timer; keystrokes produced none.
The busiest session showed 7 sub-second gaps in 112, all tool activity.

**Ringing from the `Stop` hook itself.** It looks like an obvious simplification and it announces
nothing. No hook payload carries cost, so the money would have to come from the state file, and at
the instant `Stop` fires the statusline has not been re-run with the completed request's cost in it.
On a one-request turn that request is the whole spend, and the hook would read zero. So the hook
leaves a marker and the next render rings, with the real number. That render arrives: idle sessions
keep rendering on the `refreshInterval` timer — checked across two dozen at once, every `.state` file
had been rewritten within the last second while the `.line` caches beside them were minutes old.

**Averaging the estimate.** It takes the cheapest observed ratio, not a mean or median. A minimum
cannot be dragged up by a tool-heavy turn or by a $3 cache rebuild, which is the whole point.

## Cache state

A cache read is `$0.50` per million; a 1-hour cache write is `$10`. A lapsed prefix rewrites the whole
window — observed at `$3.03` for a one-word reply, seventeen times a normal turn.

The clock starts when a request completes, which is exactly when `cost` bumps, so the statusline
already knows. The TTL itself comes from the transcript, which breaks `cache_creation` into
`ephemeral_1h_input_tokens` and `ephemeral_5m_input_tokens`; the statusline payload carries only a
flat total. That read is the one thing touching disk, paced to once per turn by `prompt_id`.

A request is classed as a rebuild when `cache_creation_input_tokens > cache_read_input_tokens` in
`current_usage`. A prefix change — an MCP server connecting or disconnecting rewrites the tool list —
causes one and cannot be predicted. A lapsed TTL causes one and can.

## Performance

`refreshInterval: 1` re-runs the statusline every second **for every open session**. Measured at 13ms
× 25 sessions ≈ 32% of a core, which is why the rendered line is cached and rebuilt only when its key
changes (`used|size|cost|prompt|minute`). Steady state is 10ms.

The remainder is `bash` and `jq` starting up, not rendering, so there is no more to shave from inside
the script. The minute counter in the key exists so a window cannot go cold behind a cached line that
still claims it is warm.

Anything added to the render path is paid once per second per session. Weigh it accordingly.

## The sound

Two accumulators carry money forward, because the eye and the ear are not on the same budget.
`pending` is money the floating number has not shown yet and flushes on the same beat it always has,
in every mode. `ring_acc` is money the ring has not announced, and what releases it is `RTC_RING`:
`immediate` (`MIN` plus `COOLDOWN`), `cumulative_threshold` (`RTC_THRESHOLD` dollars, remainder
carried by `%` so the rings do not drift quieter than asked), `on_halt` (a halt marker is present).
In `immediate` the two flush together and the behaviour is what it was before modes existed.

The whole decision — what arrived, what each accumulator now holds, whether either is due — is one
`awk`, deliberately. It replaced four, and the render path is paid once a second for every open
session: measured 16ms before, 12.5ms after.

`RTC_RING_SCOPE` decides whose money `ring_acc` is counting. Under `global`, the default, it is one
file for the machine and ten sessions ring once between them; under `session` each keeps its own.
`pending` is never shared in either — the floating number belongs to the statusline it renders on.

Sharing it makes the accumulator a read-modify-write across processes, and the statusline is a
separate process per session firing every second. Two of them reading the same `$4.95`, both adding
their bump and both crossing `$5`, is two rings and one lost write. So there is a lock, and three
things about it are load-bearing:

**It is bash's noclobber redirect, not `flock` or `mkdir`.** `flock(1)` is not on macOS and `mkdir`
costs a fork; `set -C` with `> file` opens `O_EXCL` from a builtin and writes the acquisition time in
the same syscall. Verified under contention: 16 takers, 300 rounds, exactly one winner every round.
Write the `2>/dev/null` **before** the target, not after — redirections are set up left to right, and
one written last arrives too late to swallow the `cannot overwrite existing file` the failing one
prints.

**The lock is taken on a bump, never on an idle render.** A shared file read every second by every
session and locked every second by every session would be exactly the cost this project spends its
time avoiding. The gate is: money just arrived, or this session is still carrying money it failed to
hand over, or a halt is waiting, or — in the modes where the clock alone can release a ring — the
shared accumulator is non-empty and a cooldown may have expired. A `cumulative_threshold` holding
`$2.30` for ten minutes never touches the lock. Measured: idle renders 15.2ms before the change,
15.7ms after, which is noise; bump renders 21.9ms against 23.4ms.

**A lost lock defers, it never drops.** The loser keeps the money in its own `ring_acc` and tries
again on the next render — which is why "still carrying money" is one of the gate conditions, since
by every other test that session is idle and would sit on it until it next spent. Ten sessions
piling onto the lock at the same instant is the shape of the worst case, because they render on the
same timer, so the spin is ten waits of 20ms: enough for all of them to drain in turn. Anything
holding it for more than five seconds is presumed dead and has it taken back.

`share/cash-register.wav` carries **400ms of silence in front**, and that is not padding to be
trimmed. Audio sinks suspend when idle and waking one swallows the start of a short sample — badly
over Bluetooth, where resuming the A2DP link costs hundreds of milliseconds. The register's opening
strike is in the first 50ms, so without the lead-in you hear the tail ring alone: a "ding" where a
"ka-ching" should be. `share/ATTRIBUTION.md` carries the exact ffmpeg line to regenerate it.

## Testing

There is no test suite. Drive the script with synthetic payloads on stdin — everything it needs is in
the JSON:

```bash
printf '{"session_id":"t","model":{"display_name":"Opus 5","id":"claude-opus-5"},"prompt_id":"p1",
"cost":{"total_cost_usd":10.00},"context_window":{"total_input_tokens":300000,
"context_window_size":1000000,"current_usage":{"cache_creation_input_tokens":900,
"cache_read_input_tokens":300000}}}' | RTC_MUTE=1 bin/rtc
```

Feed successive renders with rising `cost` to exercise the ring, the fade and sampling. Use a scratch
`session_id` and delete `$XDG_RUNTIME_DIR/rtc-<id>.*` between runs, or you will debug yesterday's
state. `XDG_CACHE_HOME` to a temp dir keeps a test from teaching the real model rate.

Time-dependent behaviour — fade, cache expiry — is tested by rewriting the timestamp in the state
file rather than sleeping. Rewrite it with `printf "%.6f"`; `awk`'s default output format turns an
epoch into `1.78648e+09` and the test silently stops meaning anything.

Cross-session behaviour cannot be tested that way, because the point of it is what several processes
do to one file at the same moment. Drive a dozen `session_id`s at once with `&` and `wait`, and count
rings by putting a fake `pw-play` first on `PATH` that appends a timestamp to a file — that exercises
the real `play_sound`. The two assertions worth writing: `$50` spent across ten concurrent sessions
at `RTC_THRESHOLD=5` gives exactly ten rings with nothing left carried, and no two ring timestamps
under `immediate` are closer together than `RTC_COOLDOWN`. Both failed on the first implementation.
Give the sessions an idle render or two at the end before counting, since a ring that landed on the
same instant as the last bump is delivered on the render after it.

## Releasing

```bash
# bump BOTH manifests — they are checked independently
sed -i 's/"version": "X"/"version": "Y"/' .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit && git push
claude plugin marketplace update realtokencost
claude plugin uninstall realtokencost@realtokencost
claude plugin install realtokencost@realtokencost
"$(ls -d ~/.claude/plugins/cache/realtokencost/realtokencost/*/ | sort -V | tail -1)bin/rtc" setup
```

`setup` must be re-run after every install: it writes an absolute versioned path into `statusLine`,
and the old one stops existing. Restart Claude Code afterwards — `statusLine` is read at startup, so a
running session keeps the path it started with.

Old versions stay on disk under `.../realtokencost/realtokencost/<version>/`. Always pick the highest
with `sort -V | tail -1`; `find … | head -1` returns the stale one.

**The self-chain guard must know every name this has ever had.** `setup` records the existing
statusline as a chain target, and must refuse when that target is us under an old name. The rename
from `cha-ching` walked straight into this: the guard knew only the current name, saw the abandoned
`cha-ching` binary still in the plugin cache, and chained it. Two copies rendering, both writing one
state file. If the project is ever renamed again, add the old name to that pattern.

## Prior art

The statusline space is crowded — [ccstatusline](https://github.com/sirmalloc/ccstatusline),
[TheoBrigitte](https://github.com/TheoBrigitte/claude-statusline),
[ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine) and others. All of them
show what you have already spent, and all of them take the single `statusLine` slot outright.
Prompt-cache timers exist too: a [gist by jesserobbins](https://gist.github.com/jesserobbins/ff344a13f3b90cddb8e6b1e19e7e604e)
and [claude-code-usage-bar](https://github.com/leeguooooo/claude-code-usage-bar). Both assume a
5-minute TTL — the gist says so outright, "we can't query it directly" — and neither attaches money.

What is ours: a forward-looking figure, a read TTL rather than an assumed one, a dollar cost for the
cold state, and chaining instead of replacing. Keep those distinct when changing anything; they are
the reason for the project.
