---
description: Claim the status line slot for realtokencost, keeping any status line already there
---

Wire realtokencost into this Kimi Code installation:

1. Find the plugin's managed copy: it is the directory containing `bin/rtc` under
   `$KIMI_CODE_HOME/plugins/managed/realtokencost/` (usually `~/.kimi-code/plugins/managed/realtokencost/`).
2. Run `"<that dir>/bin/rtc" setup` and then `"<that dir>/bin/rtc" doctor`.
3. Report what the two commands printed. If a previous status line command was found it is now
   chained rather than replaced, so say which one. Tell the user to run `/reload-tui`
   (or restart Kimi Code) so the new `[status_line]` takes effect.

If the doctor reports a missing dependency, say which and how to install it — `jq` is required, and
an audio player (`pw-play`, `paplay`, `aplay`, or `afplay`) is needed for the sound. Neither is
bundled. If the doctor reports no price source for the active model, relay the `RTC_PRICE_` config
line it prints — Kimi Code reports no dollar cost, so realtokencost prices measured token usage
from a rate you configure or one fetched from models.dev by `rtc rates`.
