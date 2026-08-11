# realtokencost

**What the context in front of you actually costs — before you press enter.**

A Claude Code statusline segment and hook. `rtc` for short.

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
| `RTC_COOLDOWN` | `3` | seconds between rings; spend in between accrues into the next one |
| `RTC_FADE` | `4` | seconds for the floating number to fade out |
| `RTC_MIN` | `0.005` | spend below this is not worth a sound |
| `RTC_BANDS` | `10` | announce context every N percent |
| `RTC_ESTIMATE` | `1` | `0` hides the `[~$0.18]` submit-cost figure |
| `RTC_SAMPLES` | `6` | completed turns kept to calibrate it |
| `RTC_SOUND` | bundled | path to your own wav |
| `RTC_MUTE` | `0` | `1` keeps the number, drops the sound |

Cost updates once per API response, so a tool-heavy turn would ring a dozen times. The cooldown
rate-limits the *ring*, not the accounting — spend during the quiet window accrues and lands as one
weightier number. Nothing is dropped.

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

## Requirements

- `jq`
- an audio player: `pw-play`, `paplay`, `aplay` (Linux) or `afplay` (macOS)
- Claude Code ≥ 2.1.97 for `refreshInterval`

Developed and tested on Linux. The macOS paths are written but untested — reports welcome.

## Contributing

[AGENTS.md](AGENTS.md) is the starting point — the constraints that shape the design, what the runtime
state looks like, how to drive the script without a live session, and a list of things deliberately
not done so they do not get helpfully re-added.

## Credits

The cash register is [Sound Effects Library](https://www.free-stock-music.com/sound-effects-library-cash-register-sound.html)
via free-stock-music.com, CC0. See [share/ATTRIBUTION.md](share/ATTRIBUTION.md) for the exact
preparation.

MIT.
