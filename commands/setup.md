---
allowed-tools: Bash(*/bin/cha-ching setup), Bash(*/bin/cha-ching doctor)
description: Claim the statusLine slot for cha-ching, keeping any statusline already there
disable-model-invocation: false
---

Run the cha-ching setup script:

!`"${CLAUDE_PLUGIN_ROOT}"/bin/cha-ching setup`

Then run the doctor to confirm the result:

!`"${CLAUDE_PLUGIN_ROOT}"/bin/cha-ching doctor`

Report what the two commands printed. If a previous statusline was found it is now chained rather
than replaced, so say which one. Tell the user to restart Claude Code, since `statusLine` is read at
startup.

If the doctor reports a missing dependency, say which and how to install it — `jq` is required, and
an audio player (`pw-play`, `paplay`, `aplay`, or `afplay`) is needed for the sound. Neither is
bundled.
