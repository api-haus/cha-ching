# cha-ching

Hear what Claude Code costs you, and watch the context fill.

```
Opus 5  xhigh  █░░░░░░░░░ 18%  182k / 1.00M  $9.76  [~$0.42]  +$0.03
                                                       │        ╰─ rings, then fades over 4s
                                                       ╰─ what the next message will cost
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
claude plugin marketplace add api-haus/cha-ching
claude plugin install cha-ching@cha-ching
```

The hooks wire themselves. The statusline needs one more step, because **no plugin can register a
statusline** — `statusLine` is a settings key with no plugin path. Run:

```
/cha-ching:setup
```

That claims the `statusLine` slot, sets `refreshInterval: 1` so the floating number can fade, and —
if you already had a statusline — records it as a chain target so it keeps running. Restart Claude
Code afterwards; `statusLine` is read at startup.

To do it by hand instead, or to undo it:

```bash
CC=$(ls -d ~/.claude/plugins/cache/cha-ching/cha-ching/*/ | sort -V | tail -1)bin/cha-ching
"$CC" setup       # claim the slot, chaining whatever was there
"$CC" doctor      # explain why it is quiet
"$CC" uninstall   # give the slot back
```

Installed plugins live under a version directory and old versions are kept, so the path is
`~/.claude/plugins/cache/cha-ching/cha-ching/<version>/bin/cha-ching` — hence picking the highest.

## It composes

Every statusline in this space is a total replacement: [ccstatusline](https://github.com/sirmalloc/ccstatusline),
[TheoBrigitte/claude-statusline](https://github.com/TheoBrigitte/claude-statusline),
[ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine) and the rest all want the
one slot, so you pick one and lose the others.

cha-ching chains instead. It reads the payload, harvests what it needs, then hands the same payload
to your statusline and prints what that prints:

```
statusLine.command → cha-ching ──harvest──→ bridge ──→ hooks
                          │                              │
                          └──payload──→ ccstatusline     └─→ context warnings
                                             │
                                           output ──→ appended to ours
```

Set `CHA_CHING_SEGMENT=0` and it renders nothing of its own — pure plumbing that adds a ring and a
floating number to a statusline you already like.

## Configuration

`~/.config/cha-ching/config`, one `KEY=value` per line. A real environment variable wins over the
file, because hooks and the statusline are launched by Claude Code and need not have inherited your
shell.

| Key | Default | |
|---|---|---|
| `CHA_CHING_CHAIN` | — | your statusline command; gets the same payload, output appended |
| `CHA_CHING_SEGMENT` | `1` | `0` renders nothing of ours — harvest and chain only |
| `CHA_CHING_COOLDOWN` | `3` | seconds between rings; spend in between accrues into the next one |
| `CHA_CHING_FADE` | `4` | seconds for the floating number to fade out |
| `CHA_CHING_MIN` | `0.005` | spend below this is not worth a sound |
| `CHA_CHING_BANDS` | `10` | announce context every N percent |
| `CHA_CHING_ESTIMATE` | `1` | `0` hides the `[~$0.42]` next-message estimate |
| `CHA_CHING_SAMPLES` | `6` | completed turns kept to calibrate that estimate |
| `CHA_CHING_SOUND` | bundled | path to your own wav |
| `CHA_CHING_MUTE` | `0` | `1` keeps the number, drops the sound |

Cost updates once per API response, so a tool-heavy turn would ring a dozen times. The cooldown
rate-limits the *ring*, not the accounting — spend during the quiet window accrues and lands as one
weightier number. Nothing is dropped.

## What the next message will cost

The dominant cost of your next message is re-reading the context you already have. At 800k that is
most of the bill before Claude writes a word, which is exactly the number no interface shows you
until the money is gone.

`[~$0.42]` is that figure, in blue, before you press enter. It is learned from your own session
rather than from a price table:

```
estimate = median(turn_cost ÷ turn_context) × current_context
```

`prompt_id` changes when a new prompt starts, so each completed turn yields one sample of dollars per
million tokens of context. The *ratio* is what carries to a larger window, not the dollar figure.
Median rather than mean, because one turn that read forty files should not set the expectation for
the next.

That makes it model-agnostic, plan-agnostic, and immune to rate changes — it measures what your work
actually costs instead of asserting what it should. It stays blank until three turns have completed
rather than showing a number it has not earned.

**It cannot account for what you are typing.** The statusline payload carries `prompt_id` but never
the draft text, so per-keystroke estimation is impossible — not awkward, absent. For the same reason
the estimate cannot appear only while you type: measured over a 68-second window across two dozen
live sessions, every render arrived on the `refreshInterval` timer and keystrokes produced no render
at all. There is no typing signal to key off.

## Cost of running it

`refreshInterval: 1` re-runs the statusline every second **for every open session**. Measured here:

```
13ms per render × 25 live sessions × 1/s ≈ 32% of one core
```

So the line is cached and rebuilt only when something it depends on moves, which takes a steady-state
render to 10ms and about 25%. The remainder is process startup — `bash` and `jq` — not the rendering,
so there is no clever way to shave it further from inside the script.

If you keep many sessions open, raise `refreshInterval` to 2 or 3. The only thing you lose is
smoothness in the fade. `cha-ching doctor` shows the arithmetic for your machine.

## How it works, and why it has to

Claude Code hands `cost` and `context_window` to the statusline and to nothing else. Hook payloads
carry neither. The request to expose context usage to hooks
([#27969](https://github.com/anthropics/claude-code/issues/27969)) was closed as a duplicate.

So the statusline is the only place the data exists, and it is where cha-ching sits. It parks what it
harvests in `$XDG_RUNTIME_DIR`, and the hook reads it from there. No transcript parsing, no token
counting, no price table that goes stale — the figures are the CLI's own.

That is also why the statusline step is not optional. Skip it and the plugin has no data and stays
quiet. `cha-ching doctor` will say so.

The percentage is recomputed from raw token counts rather than taken from `used_percentage`, which is
rounded to a whole number — one point is 10k tokens on a 1M window. It truncates rather than rounds,
so the figure never overstates and always agrees with the bar beside it.

## Requirements

- `jq`
- an audio player: `pw-play`, `paplay`, `aplay` (Linux) or `afplay` (macOS)
- Claude Code ≥ 2.1.97 for `refreshInterval`

Developed and tested on Linux. The macOS paths are written but untested — reports welcome.

## Credits

The cash register is [Sound Effects Library](https://www.free-stock-music.com/sound-effects-library-cash-register-sound.html)
via free-stock-music.com, CC0. See [share/ATTRIBUTION.md](share/ATTRIBUTION.md) for the exact
preparation.

MIT.
