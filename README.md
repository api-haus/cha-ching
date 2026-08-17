# realtokencost

**What the context in front of you actually costs — before you press enter.**

A statusline segment and hook for Claude Code, Kimi Code and OpenAI Codex. `rtc` for short.

```
Opus 5  xhigh  █░░░░░░░░░ 18%  182k / 1.00M  $9.76  [~$0.18]  +$0.03
                                                       │        ╰─ rings, then fades over 4s
                                                       ╰─ cost of submitting this context
```

It does not replace your statusline. It rides alongside the one you already run.

## Why

A running context is re-sent on every request. The number on screen is the *size* of the window, not
the volume you are charged for. Measured on one real session:

| | |
|---|---|
| context at the end | 831k tokens |
| API calls | 572 |
| average context re-read per call | 539k tokens |
| cache reads billed | 308.4M tokens |
| output | 0.43M tokens |
| cost | $178.89 |

The window held 831k tokens. The session was billed for 310.7M input-side tokens. What you could see
was 0.27% of what you paid for.

Nothing was mispriced — cache reads bill at a fraction of fresh input, and almost all of it was cache
reads. The cost came from volume, and volume is context size times request count. Both grow together
as a session runs, so the spend curve bends upward while the visible number crawls.

Claude Code shows a context warning only when the window is nearly full. That threshold is not
configurable: the component returns before rendering while the level is `ok`. By the time it speaks,
the expensive part already happened.

## Install

```bash
claude plugin marketplace add api-haus/realtokencost
claude plugin install realtokencost@realtokencost
```

The hooks wire themselves. The statusline needs one more step, because **no plugin can register a
statusline** — `statusLine` is a settings key with no plugin path. Run:

```
/realtokencost:setup
```

That claims the `statusLine` slot, sets `refreshInterval: 1` so the floating number can fade, and —
if you already had a statusline — records it as a chain target so it keeps running. Restart Claude
Code afterwards; `statusLine` is read at startup.

To do it by hand instead, or to undo it:

```bash
CC=$(ls -d ~/.claude/plugins/cache/realtokencost/realtokencost/*/ | sort -V | tail -1)bin/rtc
"$CC" setup       # claim the slot, chaining whatever was there
"$CC" doctor      # explain why it is quiet
"$CC" uninstall   # give the slot back
```

Installed plugins live under a version directory and old versions are kept, so the path is
`~/.claude/plugins/cache/realtokencost/realtokencost/<version>/bin/rtc` — hence picking the highest.

### Kimi Code

```bash
kimi plugins install https://github.com/api-haus/realtokencost   # or /plugins in the TUI
```

The Kimi plugin manifest wires the hooks. The status line needs the same extra step for the same
reason — `[status_line].command` lives in `tui.toml`, not in any plugin manifest — so run setup
once from the managed copy:

```bash
KC=$(ls -d ~/.kimi-code/plugins/managed/realtokencost | head -1)/bin/rtc
"$KC" setup     # writes tui.toml, fetches prices, then prints what it did
"$KC" doctor    # per-platform wiring, price provenance, the works
```

`rtc setup` detects every CLI you have installed and wires each in one run, chaining any status line
command it finds in the way, and `/reload-tui` (or a restart) picks it up.

**The money is measured, then priced — never tabled.** Kimi Code is subscription-based and reports
no dollar cost anywhere. What it does record is exact per-request token usage — input, output, cache
read, cache write — in the session's `wire.jsonl`. rtc tails that log (incrementally, from a saved
offset — idle renders cost one `stat`) and prices the measured tokens, so the float, the ring and the
`[~$…]` estimate all work exactly as they do under Claude Code.

The rates have three tiers, in order: a config line that always wins —

```
RTC_PRICE_kimi_code_k3="3 0.30 3 15"   # input cache_read cache_write output, $ per million
```

— then the models.dev cache that `rtc rates` fetches for your configured models and for any model
your subagents turn out to be running, which need not be the same list (run at setup, and
self-refreshing: a cache older than `RTC_RATES_MAX_AGE_DAYS`, default 30, triggers one detached
refetch from a render, throttled to one attempt per six hours; a failed fetch keeps the last good
numbers) — then, lowest, a bundled seed in `share/prices.tsv`, dated and limited to models with a
published first-party price, so a fresh install shows money before any fetch has run. `rtc doctor`
shows which tier every model's number came from. A model with no rate anywhere — `kimi-for-coding`
publishes no per-token price at all — gets the context gauge and warnings but no money display:
half a money figure is worse than none, and doctor prints the exact line that fixes it.

**Subagents are counted, on both.** Delegate a lot of work and most of the money stops being yours
directly — it is spent by the agents you sent out. Claude Code bills that to the session it came
from, so the figure rtc shows there always covered it. Kimi Code gives each subagent its own wire and
the main one carries none of those rows, so rtc tails the siblings too, one saved offset each, and
prices every row by the model that row names rather than by the session's. On one four-subagent
session that was $3.61 of $66.84 nobody was looking at. It joins the same total and rings the same
bell — and stays out of the estimate on purpose, because the estimate answers what submitting *your*
context costs and a subagent re-reads its own. `rtc doctor` says how much of a session's total came
from subagents, and names any subagent model it has no rate for.

What it cannot see is a *separate session*. A subagent belongs to the session that sent it, at any
depth, and is counted; a `claude -p` run started from a hook or a Bash call gets a session of its
own, and its spend is billed and shown there rather than here. Same for another local session you
reach over SendMessage. It is the same fact from both sides — the cost of a session is a number kept
by the process running it, so everything inside that process lands in it and nothing outside can. A
cloud agent launched from a workflow is the exception that proves it: Claude Code folds its usage
back in when it returns, so that one does count.

Two honest gaps. Kimi publishes no prompt-cache TTL, so on Kimi the estimate shows the warm figure
without the amber/red expiry countdown — the dollars stay measured, only the clock is missing. And
Kimi subagents inherit the model you are talking to, so while every row is priced by the model that
row names, a session mixing two of them is a case that has been built and checked rather than seen
in the wild.

### OpenAI Codex

Codex is supported, with one difference you should know before installing, because it is not a
limitation of rtc: **codex has no status line command slot.** `[tui].status_line` is a checkbox list
over built-in items — `model-with-reasoning`, `context-remaining`, `used-tokens` and so on — with no
custom entry and no plugin hook. There is nothing to claim.

So on codex the segment arrives as a hook message instead: the TUI prints it, and the model never
sees it, so it costs no tokens. You get the same line, on two beats per turn rather than once a
second.

```bash
git clone https://github.com/api-haus/realtokencost && realtokencost/bin/rtc setup
```

Then start codex, run `/hooks`, and press `t`. Codex refuses to run a hook whose command line it has
not been shown, and it skips an unreviewed one silently — so this step is not optional, and it comes
back whenever the path changes. `rtc doctor` tells you if it is outstanding.

```
[submit]  deepseek-v4-pro  █░░░░░░░░░ 16%  164k / 996k  $2.14  [~$0.18]
[stop]    deepseek-v4-pro  █░░░░░░░░░ 17%  169k / 996k  $2.35   +$0.21
```

`RTC_CODEX_RENDER` picks the beats: `submit,stop` by default, or add `tool` for a line after every
tool call, or drop one you do not want. Setup wires only the events you name, so change it and run
setup again.

**Custom models and custom providers are the normal case here, not the exception.** Codex reports
tokens and never dollars, so rtc prices them itself, reading the per-request usage out of the
session rollout and taking the model from the rollout turn by turn — so switching model mid-session
prices each request at what that request actually ran on. Rates come from `model_provider` in your
`config.toml`, which is what makes DeepSeek cost what DeepSeek charges: point codex at
`api.deepseek.com` and `rtc rates` fetches `deepseek/deepseek-v4-pro` at $0.435/M in rather than one
of the two dozen resellers listing the same name at four times that. Switch back to ChatGPT and the
same machinery prices `gpt-5.x` from OpenAI. A model with no published rate gets the gauge and the
warnings but no money display, and `rtc doctor` prints the `RTC_PRICE_…` line that fixes it.

**Check the fetched rate against your provider's own table once.** models.dev is the automatic
source and it is not right about everyone. For `deepseek-v4-pro` on 2026-08-17 it published $0.435/M
in and $0.87/M out; DeepSeek charges $0.66/$1.98 off-peak and $1.32/$3.96 at peak — so the fetched
number was low by 1.5× for most of the day and 3× during peak hours. `rtc doctor` names the source
of every rate it is using; if it disagrees with your bill, state the truth once and it wins forever:

```
RTC_PRICE_deepseek_v4_pro="1.32 0.044 0 3.96 0.66 0.022 0 1.98"
RTC_PEAK_deepseek_v4_pro="01-04,06-10"
```

Eight numbers instead of four is a provider that charges by the clock — peak four, then off-peak
four — and `RTC_PEAK_<model>` says when the first half applies, in UTC. DeepSeek halves its rates
outside those two windows, so no single figure is correct at every hour. Doctor prints which half is
in force right now.

Money below a cent is shown to four decimals rather than two, because a whole DeepSeek turn is a
third of a cent and `$0.00` reads like a broken tool rather than a cheap one.

Two honest gaps here too. Codex publishes no prompt-cache TTL, so the estimate shows the warm figure
with no expiry countdown. And codex subagents are **not** counted: no session on this machine has
ever used `multi_agent`, so whether a child's tokens reach the parent rollout is untested, and rtc
claims nothing it has not measured. On a delegating codex session, read the total as a floor.

OpenCode is not supported yet: it has no statusline-command integration point
([opencode#30295](https://github.com/anomalyco/opencode/issues/30295)). When one lands, rtc's
platform layer is where it goes.

## It composes

Every statusline in this space is a total replacement: [ccstatusline](https://github.com/sirmalloc/ccstatusline),
[TheoBrigitte/claude-statusline](https://github.com/TheoBrigitte/claude-statusline),
[ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine) and the rest all want the
one slot, so you pick one and lose the others.

RTC chains instead. It reads the payload, harvests what it needs, then hands the same payload
to your statusline and prints what that prints:

```
statusLine.command → realtokencost ──harvest──→ bridge ──→ hooks
                          │                              │
                          └──payload──→ ccstatusline     └─→ context warnings
                                             │
                                           output ──→ appended to ours
```

Set `RTC_SEGMENT=0` and RTC renders nothing of its own — pure plumbing that adds a ring and a
floating number to a statusline you already like.

## Configuration

`~/.config/realtokencost/config`, one `KEY=value` per line. A real environment variable wins over the
file, because hooks and the statusline are launched by Claude Code and need not have inherited your
shell.

| Key | Default | |
|---|---|---|
| `RTC_CHAIN` | — | your statusline command; gets the same payload, output appended |
| `RTC_SEGMENT` | `1` | `0` renders nothing of ours — harvest and chain only |
| `RTC_RING` | `immediate` | what releases the sound — see below |
| `RTC_RING_SCOPE` | `global` | `session` counts and announces each session's spend on its own |
| `RTC_THRESHOLD` | `5` | dollars per ring under `cumulative_threshold` |
| `RTC_COOLDOWN` | `3` | seconds between rings; spend in between accrues into the next one |
| `RTC_FADE` | `4` | seconds for the floating number to fade out |
| `RTC_MIN` | `0.005` | spend below this is not worth a sound |
| `RTC_BANDS` | `10` | announce context every N percent |
| `RTC_ESTIMATE` | `1` | `0` hides the `[~$0.18]` submit-cost figure |
| `RTC_SAMPLES` | `12` | recent requests kept to calibrate it |
| `RTC_SOUND` | bundled | path to your own wav |
| `RTC_VOLUME` | `0.8` | loudness, `0`-`1`; `aplay` has no per-call gain and ignores it |
| `RTC_MUTE` | `0` | `1` keeps the number, drops the sound |
| `RTC_PRICE_<model>` | — | Kimi and codex: `input cache_read cache_write output` in $/M, or eight values for peak-then-off-peak. Beats the cache and the seed |
| `RTC_PEAK_<model>` | — | UTC windows the first four rates apply in, e.g. `01-04,06-10`; `22-02` runs past midnight. `RTC_PEAK` sets a default for every model |
| `RTC_RATES_MAX_AGE_DAYS` | `30` | price cache older than this self-refreshes on the next render |
| `RTC_RATES_REFRESH` | `1` | `0` disables that auto-refresh |
| `RTC_CODEX_RENDER` | `submit,stop` | codex only: which hook events print a line — `submit`, `tool`, `stop`. Setup wires only these, so re-run it after a change |

## When it rings

Cost updates once per API response, so a tool-heavy turn moves money a dozen times. What that should
sound like depends on what you are doing, so `RTC_RING` picks:

| `RTC_RING` | rings |
|---|---|
| `immediate` | on every bump over `RTC_MIN`, at most one per `RTC_COOLDOWN` |
| `cumulative_threshold` | once per `RTC_THRESHOLD` dollars, however long that takes |
| `on_halt` | when the turn hands back — work submitted, question asked, permission wanted |

`immediate` is the default and is a live wire: you hear the session working, and a run of tool calls
you did not expect announces itself while it is happening.

`cumulative_threshold` is for long unattended runs, where the immediate ring becomes a metronome you
stop hearing. One ring per `$5` is a budget you notice instead.

`on_halt` inverts it. Nothing during the work, one ring at the moment the turn needs you, which is
the moment you would want to look up anyway. Wired to the `Stop` and `Notification` hooks, so a
permission prompt rings too — that is Claude waiting on you with money already spent.

Rate-limiting is applied to the ring, never to the accounting. Spend during a quiet stretch accrues
and lands with the next one, and a threshold carries its remainder, so every `$5` spent is one ring
however the bumps happened to fall.

The floating number keeps its own rhythm in all three. It is free — it costs a glance you are already
giving the statusline — while a sound interrupts, so only the sound is worth moving.

## One ring for the machine

Ten sessions open at once are still one person spending, one pair of ears and one budget. So the
accumulator and the cooldown are shared: one ring per `$5` across every session on the machine, one
ring per `RTC_COOLDOWN` seconds across every session, rung by whichever session happens to be the one
that crosses the line. `RTC_RING_SCOPE=session` gives each session its own accumulator and its own
clock, which is what this did before the switch existed.

The floating number is never shared. It costs a glance rather than an interruption, and it belongs to
the statusline it appears on — nobody wants their spend announced on somebody else's line.

The shared state is two numbers in a file, and every session takes a lock before touching it: bash's
`O_EXCL` redirect, held for one read and one write. A session that cannot get the lock keeps its
money and comes back on the next render a second later, so a ring is delayed rather than dropped. A
session killed while holding it has the lock taken back after five seconds. `rtc doctor` prints what
is carried, how long ago the last ring was, and whether anything holds the lock right now.

## What it costs to submit

`[~$0.18]` is the bare cost of sending your current context, before Claude writes a word. The whole
window is re-read on every request, so this is already spent the moment you press enter — it is the
price of the conversation you are carrying, not of the question you are asking.

**It deliberately does not predict the turn.** Whether Claude replies in one word or makes twenty
tool calls is a property of the work, not of the context, and no history predicts it. An earlier
version showed a range whose upper bound was exactly that guess; it was removed. The number you can
know is the one that is fixed before the request is sent.

It is learned rather than looked up. `prompt_id` changes when a new prompt starts, so each completed
turn yields one sample of dollars per million tokens of context, and the cheapest turn observed
approximates a bare submit — one API call, a submit plus a few tokens of reply. Turns that did real
work are strictly dearer and cannot drag it down.

Checked against first principles on a live session: the learned figure said `$0.18` where
`332,258 tokens × $0.50/M` gives `$0.17`, with no price table anywhere in RTC. That is the
point — it stays correct across models, plans and rate changes because it measures instead of
asserting.

The figure is measured per request rather than per turn, so it appears within seconds of a session's
first response instead of after two completed turns.

What a bare submit costs per million tokens is a property of the model rather than of the session —
it is essentially the cache-read rate — so it is learned once and kept in
`~/.cache/realtokencost/rate-<model>`. A new session inherits it and shows a figure on its first
render, then prefers its own turns as they accumulate. Only ordinary turns teach it; a rebuild
describes an event and is excluded.

The figure is dimmed until three turns have landed. `rtc doctor` reports calibration per session,
never totalled across them, plus what each model has learned.

**It cannot account for what you are typing.** The payload carries `prompt_id` but never the draft
text. For the same reason the figure cannot appear only while you type: measured over a 68-second
window across two dozen live sessions, every render arrived on the `refreshInterval` timer and
keystrokes produced none at all. There is no typing signal to key off.

### The price has two values, and which one you get is knowable

A cache read is `$0.50` per million tokens. A cache *write* on the 1-hour TTL is `$10` — twenty times
dearer. So submitting the same window costs one of two very different amounts depending on whether
the cache is still alive, and realtokencost tracks which:

```
[~$0.19]         blue    cached. re-read at read rate.
[~$0.19 · 4m]    amber   4 minutes before it lapses
[~$3.16 ⟳]       red     lapsed. the next submit rewrites the whole window.
```

The clock starts when the last request completed, and the TTL is read from the transcript, which
breaks `cache_creation` out into `ephemeral_1h_input_tokens` and `ephemeral_5m_input_tokens`. The
statusline payload carries only a flat total, so this is the one thing read from disk — once per
turn, never per render.

The cold figure prefers a rebuild this session has actually suffered over an asserted ratio. Measured
against a real one: predicted `$3.16`, paid `$3.030`.

Because that rebuild is what a lapse costs. Observed on a live session, for a one-word reply:

```
normal turn      cache_read  324,345 × $0.50/M  =  $0.162
                 cache_write   1,733 × $10.00/M =  $0.017   → $0.180
after a rebuild  cache_read   26,289 × $0.50/M  =  $0.013
                 cache_write 301,730 × $10.00/M =  $3.017   → $3.030
```

Seventeen times a normal turn, for the word "pong". A lapsed TTL is one way to get there. So is
anything that changes the prompt prefix — an MCP server connecting or disconnecting rewrites the tool
list, and every cached token behind it has to be paid for again. That one is not predictable, which
is why rebuild turns are filed separately and can never drag the warm figure down.

## Cost of running it

`refreshInterval: 1` re-runs the statusline every second **for every open session**. Measured here:

```
13ms per render × 25 live sessions × 1/s ≈ 32% of one core
```

So the line is cached and rebuilt only when something it depends on moves, which takes a steady-state
render to 10ms and about 25%. The remainder is process startup — `bash` and `jq` — not the rendering,
so there is no clever way to shave it further from inside the script.

If you keep many sessions open, raise `refreshInterval` to 2 or 3. The only thing you lose is
smoothness in the fade. `rtc doctor` shows the arithmetic for your machine.

## How it works, and why it has to

Claude Code hands `cost` and `context_window` to the statusline and to nothing else. Hook payloads
carry neither. The request to expose context usage to hooks
([#27969](https://github.com/anthropics/claude-code/issues/27969)) was closed as a duplicate.

So the statusline is the only place the data exists, and it is where RTC sits. It parks what it
harvests in `$XDG_RUNTIME_DIR`, and the hook reads it from there. No transcript parsing, no token
counting, no price table that goes stale — the figures are the CLI's own.

That is also why the statusline step is not optional. Skip it and the plugin has no data and stays
quiet. `rtc doctor` will say so.

The percentage is recomputed from raw token counts rather than taken from `used_percentage`, which is
rounded to a whole number — one point is 10k tokens on a 1M window. It truncates rather than rounds,
so the figure never overstates and always agrees with the bar beside it.

Kimi and codex are the same shape with the money the other way round. Neither reports a dollar, and
both record exact per-request token usage — Kimi in the session's `wire.jsonl`, codex in the session
rollout the hook payload names. rtc tails that file from a saved byte offset, prices the new rows by
the model each row names, and everything downstream — the float, the ring, the estimate — works
unchanged. On codex there is no per-second slot to render into, so the same code runs from the hooks
and rings from `Stop`, which is safe there precisely because the hook reads the completed request out
of the rollout rather than waiting for a render that is never coming.

## Requirements

- `jq`
- an audio player: `pw-play`, `paplay`, `aplay` (Linux) or `afplay` (macOS)
- Claude Code ≥ 2.1.97 for `refreshInterval`, Kimi Code ≥ 0.30 for `[status_line].command`, and/or
  Codex ≥ 0.147 for lifecycle hooks. `curl` too, if you want prices fetched rather than set by hand.

Developed on Linux. macOS is exercised in two halves rather than on a Mac — a BSD-shaped `PATH` with
no `setsid` and no `tac`, and bash 3.2.57, which is still what `/bin/bash` is there. Both halves run
the full drive suite; before 2.7.0 both were failing, and the ring had never made a sound on a Mac.
Reports from a real one are still welcome.

## Contributing

[AGENTS.md](AGENTS.md) is the starting point — the constraints that shape the design, what the runtime
state looks like, how to drive the script without a live session, and a list of things deliberately
not done so they do not get helpfully re-added.

`./drive/matrix.sh` runs the whole suite on every platform this supports, which takes about ninety
seconds and includes macOS in the only two forms available off a Mac: a BSD-shaped `PATH` with no
`setsid` and no `tac`, and bash 3.2.57 in a container. Run it before opening a pull request.
`./drive/mutate.sh` breaks one line of `bin/rtc` at a time and checks the suite notices — if you add
a rule, add a mutant for it.

## Credits

The cash register is [Sound Effects Library](https://www.free-stock-music.com/sound-effects-library-cash-register-sound.html)
via free-stock-music.com, CC0. See [share/ATTRIBUTION.md](share/ATTRIBUTION.md) for the exact
preparation.

MIT.
