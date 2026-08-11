---
allowed-tools: Bash(*/bin/rtc setup), Bash(*/bin/rtc doctor)
description: Claim the statusLine slot for realtokencost, keeping any statusline already there
disable-model-invocation: false
---

Run the rtc setup script:

!`"${CLAUDE_PLUGIN_ROOT}"/bin/rtc setup`

Then run the doctor to confirm the result:

!`"${CLAUDE_PLUGIN_ROOT}"/bin/rtc doctor`

Report what the two commands printed. If a previous statusline was found it is now chained rather
than replaced, so say which one. Tell the user to restart Claude Code, since `statusLine` is read at
startup.

If the doctor reports a missing dependency, say which and how to install it — `jq` is required, and
an audio player (`pw-play`, `paplay`, `aplay`, or `afplay`) is needed for the sound. Neither is
bundled.
