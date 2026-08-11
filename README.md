# cha-ching

Hear what Claude Code costs you, and watch the context fill.

```
Opus 5  xhigh  █░░░░░░░░░ 18%  182k / 1.00M  $9.76  +$0.03
                                                     ╰─ rings, then fades over 4s
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
CC=$(find ~/.claude/plugins/cache/cha-ching -name cha-ching -type f -perm -u+x | head -1)
"$CC" setup       # claim the slot, chaining whatever was there
"$CC" doctor      # explain why it is quiet
"$CC" uninstall   # give the slot back
```

Installed plugins live under a version directory, so the path is
`~/.claude/plugins/cache/cha-ching/cha-ching/<version>/bin/cha-ching` — hence the `find`.

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
| `CHA_CHING_SOUND` | bundled | path to your own wav |
| `CHA_CHING_MUTE` | `0` | `1` keeps the number, drops the sound |

Cost updates once per API response, so a tool-heavy turn would ring a dozen times. The cooldown
rate-limits the *ring*, not the accounting — spend during the quiet window accrues and lands as one
weightier number. Nothing is dropped.

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
