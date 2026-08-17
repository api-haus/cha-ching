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

Setup wires every CLI it finds, so if it reported a codex section, say that codex needs one more
step before its hooks will run at all: start codex, run `/hooks`, press `t`. Codex skips a hook it
has not been shown without saying anything, and it asks again whenever the command line changes.

If the doctor reports a missing dependency, say which and how to install it — `jq` is required, and
an audio player (`pw-play`, `paplay`, `aplay`, or `afplay`) is needed for the sound. Neither is
bundled.
