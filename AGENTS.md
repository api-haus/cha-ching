# AGENTS.md

realtokencost (`rtc`) is a plugin for Claude Code and Kimi Code: a statusline segment plus a hook.
It shows what submitting the current context costs *before* you press enter, whether the prompt
cache is still alive to make that the cheap number, rings a cash register when money moves, and
warns as the window fills. `README.md` is written for users; this file is what you need to change
the thing.

Everything below was verified against Claude Code 2.1.227 and Kimi Code 0.34.0 by reading the
binaries and live payloads. Where a claim is checkable, the check is named. Re-verify rather than
trust if a claim starts costing you time — both CLIs move.

## The constraints that shape the design

Read these before proposing an architecture change. Each one has already been paid for.

**A plugin cannot register a statusline.** `statusLine` is a settings key with no plugin path —
there is no `pluginStatusLine` identifier in the binary. Hooks install themselves via
`hooks/hooks.json`; the statusline needs `rtc setup` to write `settings.json`. This asymmetry is why
setup exists at all. Kimi Code has the same asymmetry with different names: `kimi.plugin.json`
carries hooks but `[status_line].command` lives in `tui.toml`, which only setup writes.

**Hook payloads carry neither cost nor context.** `cost.total_cost_usd` and `context_window` are
handed to the statusline and to nothing else. The request to expose context usage to hooks
([anthropics/claude-code#27969](https://github.com/anthropics/claude-code/issues/27969)) was closed as
a duplicate. So the statusline harvests to files under `$XDG_RUNTIME_DIR` and the hook reads them
there. That bridge is not a workaround to be cleaned up; it is the only path. Kimi is the same
shape: the snapshot carries context, the hooks carry `session_id` and nothing else.

**Kimi reports tokens, never dollars.** Kimi Code is subscription-based; no payload, wire record or
API exposes a cost. The money features survive because the session's
`$KIMI_CODE_HOME/sessions/*/session_<id>/agents/main/wire.jsonl` records one `usage.record` row per
request — `inputOther`, `output`, `inputCacheRead`, `inputCacheCreation` — and measured tokens
times a rate is a price. Rates have three tiers, strict order: `RTC_PRICE_<model>` in the config
(always wins), the `price-<model>` cache `rtc rates` writes from models.dev, the bundled seed in
`share/prices.tsv`. A model with no rate anywhere gets gauge and warnings only; a half-shown money
display is worse than none. Kimi publishes no cache TTL, so there the estimate never shows the
expiring/cold countdown.

**Never let a shipped price outrank a measured or fetched one.** The CLI has a price table compiled
in (`inputTokens:5, outputTokens:25, promptCacheWriteTokens:6.25, promptCacheWrite1hTokens:10,
promptCacheReadTokens:0.5` per million) and it is exactly what goes stale — Anthropic added the 1-hour
cache tier and the read/write spread became 20×, not 20%. So Claude dollars are measured from the
host, never priced: each request bump says this much money bought a re-read of this much context.
Validated against first principles on a live session — learned `$0.18` where `332,258 × $0.50/M`
gives `$0.17`.

For Kimi there is nothing to measure dollars *from*, so after shipping rate-less for a version the
owner called for a bundled seed (2026-08, the discussion is in the git log). It is kept honest by
construction rather than by promise: last precedence (any config or cache line beats it), dated in
the file, limited to models with a published first-party price — `kimi-for-coding` lists $0
everywhere, so it gets no invented number — and self-replacing: a seed-sourced or
`RTC_RATES_MAX_AGE_DAYS`-stale price makes the next render spawn one detached `rtc rates`
(throttled to one attempt per six hours by `$CACHE_DIR/.rates-when`; a failed fetch keeps the last
good numbers). `price_for` reports its tier in `PRICE_SRC` and doctor shows it, so a stale number
is never silently stale. When editing the seed, update its bundle date — the date is the freshness
bound.

**macOS is supported and cannot be run here, so it is simulated in two halves.** Both halves found
real bugs, so run both before believing a platform claim. `drive/matrix.sh` does it: a macOS-shaped
`PATH` holding only the utilities macOS ships — BSD-behaving `stat` and `date`, and crucially no
`setsid` and no `tac` — and bash 3.2.57 in a container, which is still what `/bin/bash` is there.
What that turned up in 2.6.0, all three shipped and all three dead on arrival on a Mac:

`setsid` is util-linux. macOS has none, and `(setsid "$p" "$wav" &)` there is not a degraded detach
but no detach at all — the ring was silent on every Mac since the feature existed, and the
self-refreshing price fetch never ran either. A background subshell orphans the child just as well;
`setsid` only adds a new session, so it is used where it exists and skipped where it does not.

BSD `date` has no `%N` and hands the conversion back unexpanded, so `now_s` returned
`1786499706.N`. Every numeric guard downstream then read that as zero: the shared ring's last-ring
time became 0 and stopped enforcing the cooldown, and a live lock holder's stamp became 0, so the
next session to want the lock decided the holder had died and took it. The mutex below was defeated
on every render. Driven at ten concurrent sessions spending $50 at a $5 threshold, the shipped 2.6.0
under a BSD userland rings **zero** times and strands $3 in the shared accumulator; trimming
`now_s` to its leading number gives the ten rings and nothing carried.

`readlink -f` only reached macOS in 12.3, and the fallback kept whatever `$0` was — which `setup`
then writes into `settings.json`, and which `ROOT` (the price seed, the wav) is derived from. It is
made absolute now.

**`LC_ALL=C` at the top of the script is load-bearing.** Money and percentages are text all the way
through. Under a comma-decimal locale `awk` and `printf` disagree about what `9.76` means and the
arithmetic silently stops working. Found on a Ukrainian-locale shell.

**One API response writes several transcript records.** Text, thinking and each `tool_use` block get
their own record. Any transcript analysis must `group_by(.message.id)` first. Summing records
inflated a measurement by roughly half before this was caught. Kimi's wire is the opposite
discipline: only `usage.record` rows count, and the same usage also appears inside
`context.append_loop_event` `step.end` events — summing those would double it.

**Grouping is not enough: the reducer must be `max`.** Those records do *not* all carry the same
`usage` object, which this file claimed until it was measured. They are streamed snapshots.
`input_tokens`, `cache_read_input_tokens` and `cache_creation_input_tokens` are constant within a
`message.id`, but `output_tokens` **grows**, and the last record holds the final figure. On one
120-response transcript: summing every record gives 50626 output tokens, `max` (equivalently `last`)
per id gives the true 50264, and `first` per id gives **9014** — a 5.6× undercount from the reducer
alone. Verified across a dozen transcripts and two models. The tempting shortcut — count only the
records whose usage carries an `iterations` array — is wrong too: 30 of those 120 responses have no
such record at all, and it undercounts cache-write by 15%. Same-id records are always contiguous in
the file, so an incremental reader only ever has one straddling group to think about.

**Claude's `total_cost_usd` already contains subagent spend.** Do not add a derived figure to it.
The CLI keeps the session's cost in one process-global counter — `mn.totalCostUSD` in 2.1.228, where
`mn` is a plain module singleton, not anything scoped per agent — and exactly one function adds to
it, reached from one place: the accounting that runs when an API response completes. So there is no
per-agent partition for a rollup to miss. Every request the process makes credits the same number,
whatever spawned it and however deep.

Measured to agree on a live session carrying a three-deep `Task` chain and two `workflow-subagent`
agents: the parent transcript alone reaches 93.9% of the host's figure, and adding the five child
transcripts closes it to 99.996%. Earlier, on eight sessions of `Explore`, `general-purpose` and
custom agents at depth 1, priced from models.dev instead: 73–94% and 98.7–100.0%, calibrated against
three subagent-free sessions to within 0.05%. The upstream issues that say child sessions never roll
up ([claude-code#48040](https://github.com/anthropics/claude-code/issues/48040),
[#60591](https://github.com/anthropics/claude-code/issues/60591)) no longer describe the shipping
CLI.

To re-run that check, price the transcripts with the table the CLI compiles in
(`inputTokens:5, outputTokens:25, promptCacheWriteTokens:6.25, promptCacheWrite1hTokens:10,
promptCacheReadTokens:0.5`) rather than with models.dev — reproducing the host's own arithmetic is
the one job that table is right for, and then a shortfall means a transcript nobody read rather than
a rate that moved. That is the opposite of what the rule above forbids, which is showing a user a
compiled price. The only place a cost figure exists is the statusline payload, so the check needs a
*live* session with rtc running: its state file holds the host's number and the transcripts hold the
tokens. Nothing on disk records cost otherwise (`history.jsonl` is prompt text, `stats-cache.json`
is aggregate token counts, and no transcript record carries a cost field).

Every child transcript lives under the parent session's directory, and there are exactly four path
shapes in `~/.claude/projects/<slug>/`:

```
<session>.jsonl                                the parent
<session>/subagents/agent-<id>.jsonl           Task subagents — every depth, every agent type
<session>/subagents/workflows/<wf>/agent-<id>.jsonl   Workflow tool agents
<session>/subagents/workflows/<wf>/journal.jsonl      the workflow journal, no usage in it
```

Two traps in that. **Nesting does not nest**: an agent that spawns an agent that spawns an agent
gives `spawnDepth` 1, 2 and 3 side by side in one flat `subagents/`, all carrying the *root*
session's id in their `sessionId` — a child transcript never names itself there. **Workflow agents
do nest**, one level deeper under `subagents/workflows/<wf>/`, so a flat `subagents/*.jsonl` glob
misses them; the complete sweep is `subagents` recursively for `agent-*.jsonl`.

Agent forms covered by measurement: `Explore`, `general-purpose` and custom (`research-*`) types at
depth 1, `Task` at depths 2 and 3, and `workflow-subagent`. `fork` has not been run against the
host's number, and needs no separate check unless the counter above stops being one counter — it
issues its requests from the same process as everything else.

A remote workflow agent is **not** outside the accounting, which this file used to claim. When a
`workflow_remote_agent` cloud session finishes, the CLI walks its per-model usage and hands each
entry to the same function that credits an ordinary response, so the spend arrives in
`total_cost_usd` on the parent — late, in one lump, at the moment the agent returns.

Genuinely outside it, on both platforms: anything that is a *separate session* rather than a child of
this one — a `claude -p` run started from a hook or a Bash call, another local session reached over
SendMessage. Their spend is billed to their own session, and a headless one has no statusline for rtc
to sit in, so nothing sees it. That is a property of where rtc lives, not a bug in the accounting.

**The version must bump for an update to reach an install.** Refreshing a marketplace does not
re-fetch a plugin whose version has not moved. A fix left at the same version sits unreachable; this
has already happened once.

**Platform is detected from the payload, never configured.** A statusline payload with `sessionId`
(camelCase) is Kimi; `session_id` (snake) is Claude. A hook payload with `hook_event_name` is Kimi.
Kimi hook stdout must be plain text (it is appended to context verbatim); Claude wants
`{"systemMessage": ...}` JSON. Kimi session files are prefixed `rtc-kimi-` so state never collides
and `doctor` can tell them apart.

## Layout

```
bin/rtc                      everything — one bash script, seven subcommands
hooks/hooks.json             Claude: UserPromptSubmit -> rtc hook; Stop, Notification -> rtc halt
kimi.plugin.json             Kimi plugin manifest: same three hooks, ./kimi/commands/
commands/setup.md            /realtokencost:setup (Claude)
kimi/commands/setup.md       /realtokencost:setup (Kimi — command bodies are prompts there,
                             so this one tells the agent how to find the managed copy)
share/cash-register.wav      CC0, see share/ATTRIBUTION.md
share/prices.tsv             bundled Kimi price seed — last precedence, dated, see the
                             price rule under "constraints" before touching it
drive/matrix.sh              every drive on every supported platform — see "Testing"
drive/lib.sh                 the scratch world each drive runs in, and the second
                             arithmetic their expected figures come from
.claude-plugin/plugin.json   plugin manifest
.claude-plugin/marketplace.json   single-plugin marketplace, source "./"
```

`rtc statusline` is what the status line command runs (`statusLine.command` on Claude,
`[status_line].command` on Kimi). `rtc hook`, `halt`, `setup`, `uninstall`, `rates`, `doctor` are
the rest. `rates` fetches what models.dev publishes into
`$XDG_CACHE_HOME/realtokencost/price-<model>` — the Kimi money source alongside `RTC_PRICE_*`. It
takes its roster from two places, and needs both: the `[models.*]` tables in Kimi's `config.toml`,
and every alias a live wire has actually reported, read off the `.wire` and `.subs` sidecars.
Nothing configures the model a subagent runs, so an alias that arrives only on that agent's own
`usage.record` rows has no table to be found in, and before this it could never get a price file at
all — its spend went missing from a session whose own model looked fine. A wire-discovered alias has
no model id to pair with either, so its last path segment stands in: `kimi-code/k3` asks models.dev
for `k3`, and the lookup already tries the `kimi-` prefix beside it.
`doctor` exists to answer "why is it quiet" without a debugging session —
extend it when you add a way for things to be quiet. Every ring mode is one such way, and so is a
shared ring, which is why each prints its own line there. A Kimi model with no rate is another —
doctor prints the per-model provenance and the exact config line that fixes a missing one.

**Nothing counts sessions by counting files.** Nothing ever deletes a state file — it lives until
`$XDG_RUNTIME_DIR` is cleared at logout — so a glob counts every session the machine has run since
then. `doctor` was reporting 27 sessions and a third of a core against three live ones, and telling
the user to raise `refreshInterval` on the strength of it. A live session rewrites its state on every
render, so liveness is recency: `find "$RUN" -maxdepth 1 -name 'rtc-*.state' -mmin -1`. Use `-mmin`
rather than `-newermt`, which is a GNU spelling that silently returns nothing under `bfs`.

## Runtime state

Per session under `$XDG_RUNTIME_DIR` (falling back to `TMPDIR`), keyed by `session_id`. Kimi
sessions use the same files with an `rtc-kimi-` prefix instead of `rtc-`:

| file | holds |
|---|---|
| `rtc-<id>.state` | twelve space-separated fields, order below |
| `rtc-<id>.turns` | recent ordinary request ratios, `$` per million tokens of context |
| `rtc-<id>.rebuilds` | ratios from requests that rebuilt the cache — a different thing entirely |
| `rtc-<id>.ctx` | `used size`, the bridge the hook reads |
| `rtc-<id>.line` | cache key on line 1, rendered segment on line 2 |
| `rtc-<id>.band` | highest context band already announced |
| `rtc-<id>.halt` | the turn handed back; consumed by the next render |
| `rtc-<id>.nudged` | set once when told to run setup |
| `rtc-kimi-<id>.wire` | Kimi only: wire.jsonl path on line 1, model alias on line 2 |
| `rtc-kimi-<id>.subs` | Kimi only: one line per subagent wire — `agent-N offset alias` |

State field order, positional, read with one `read`:

```
cost pending ring_ts shown shown_ts prev_prompt turn_cost turn_ctx last_call ttl ring_acc woffset sacc
```

`woffset` is the Kimi wire.jsonl byte offset; 0 on Claude. On Kimi `cost` is not host-reported —
it is the running total rtc maintains by pricing new `usage.record` rows, and a first sight of a
wire adopts its current size as the offset rather than announcing history (the same rule as a first
cost sighting). The wire path lives in a side file, not the state file, because paths can contain
characters the positional format cannot.

`sacc` is how much of `cost` came from subagents. It is what doctor reports and it is never
subtracted from anything — subagent money is the session's money. The sibling offsets are not in
here either, for the same reason as the wire path plus one more: there is one per wire and the
format is a single line.

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

## Subagent spend

Both platforms count it. They arrive there differently, and the difference is the whole story.

**Claude counts it for free.** `cost.total_cost_usd` already includes what the children spent, so rtc
adds nothing and reads no child transcript. The constraint above has the measurement; doctor prints
one line saying so, because "are my subagents counted" is the obvious question and a silent yes reads
the same as a no.

**Kimi has to be told.** Every subagent gets its own
`$KIMI_CODE_HOME/sessions/<proj>/session_<id>/agents/agent-<N>/wire.jsonl`, carrying the same
`usage.record` rows the main tailer already prices, and the main wire carries none of them: on a live
four-subagent session, 581 rows in `agents/main` against 96 across the siblings, with not one `time`
key shared between them. Since the Kimi total is a figure rtc computes rather than one it harvests,
that money was simply absent. On that session it was $3.61 of $66.84 — 5.4%.

So `kimi_subagents` tails the siblings the way `kimi_main_delta` tails main, with the same four
rules: adopt on first sight, never recount history, leave a partial last line for the next render,
and treat `size < offset` as a rotation and adopt again. Each wire keeps its own offset, because each
starts and ends on its own schedule. Three things are worth knowing before changing it:

- **A wire that appears after the session's first render is not history.** It is a subagent that has
  just been spawned, and every byte of it belongs to this session, so it starts at offset 0. Only on
  the very first render — when `last` is empty and main is adopting too — do the siblings adopt their
  current size. Getting this backwards loses the first subagent of every session.
- **Rows are priced by the model each row names**, not by the session's model. A subagent may run
  something the main agent never touches — a Kimi task carries its own `model` beside its
  `subagent_type`, and an agent profile sets one with `model_preference` — which is also why a
  subagent model with no rate is its own doctor line: the total goes quietly short while the
  session's own model looks fine. A wire that names a model with no rate also asks for a fetch, on
  the same terms the main model gets and under the same six-hour throttle, so the gap closes itself
  on the next render instead of waiting for someone to read doctor.

  A mixed session has still never been seen here, and the reason is worth knowing before hunting for
  one: a Kimi subagent inherits the session's model. Driven live with `-m` both ways, main and
  `agent-0` came out matching each time, and 12,453 of the 12,552 `usage.record` rows on this machine
  name `kimi-code/k3` with the other 99 on main wires of sessions that ran `kimi-for-coding` whole.
  An agent profile with `model_preference` did not change it — the CLI answered that the profile
  "isn't available" and fell back to the generic `agent`, which is a discovery question nobody has
  chased. So the per-row path is verified on real rows carrying both real aliases rather than on a
  live mixed session, and the thing that keeps it honest is that a task carries its own `model`, so
  the day one arrives, nothing needs to change to count it.
- **Subagent money never reaches the estimate.** It moves `cost`, so the ring and the floating number
  see it, but `record_sample` and `last_call` are driven by the main agent's share alone (`mainbump`,
  which the money `awk` returns beside the total bump). A subagent request re-reads its own context,
  not this one — feeding it in would inflate the dollars-per-million ratio the estimate is built from
  and restart a cache clock that never stopped.

The sidecar is keyed by directory name (`agent-0`), never by path: the path is rebuilt from main's,
so no field can contain a space and the whole file parses with `read`.

## Things deliberately not done

Do not "fix" these. Each was tried or considered and rejected for a reason.

**OpenCode support.** It has no statusline-command integration point — the SolidJS status bar has no
user slot, and the request for one
([anomalyco/opencode#30295](https://github.com/anomalyco/opencode/issues/30295)) is open. The plugin
API is TypeScript with toasts, which would be a second codebase for half the features. When a
statusline slot lands, the payload-detection branch in `cmd_statusline` is where it plugs in.

**A Claude-side subagent rollup.** Counting it would count it twice — see the `total_cost_usd`
constraint above, which was measured rather than assumed. Claude sessions therefore run none of the
subagent code at all, and the render path there is untouched.

**Learning Kimi's cache TTL.** No payload or wire record names it, and the hint dialog in the TUI
proves the CLI knows it but does not print it. It could be bounded empirically (a rebuild after an
idle gap is an upper bound, a hit a lower one) — deliberately not yet; the estimate simply shows the
warm figure there.

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

The Kimi subagent pass is priced the same way. Measured over 40 renders each, idle (nothing appended,
which is the steady state):

| session | before | after |
|---|---|---|
| Kimi, no subagents | 15.3ms | 16.0ms |
| Kimi, 4 subagent wires | 15.5ms | 17.8ms |
| Kimi, 16 subagent wires | 15.3ms | 18.9ms |
| Claude | unchanged | unchanged |

The macOS fixes cost nothing on top of that: 12.6ms against 12.2ms with no subagents, 18.1ms against
18.5ms with four wires, over 40 idle renders each, which is noise. `now_s` still forks `date` once
and only once, because it trims what BSD hands back rather than probing with a second call, and the
`setsid` question is answered by a builtin.

A session with no subagents pays nothing measurable, because the probe that decides whether to go on
is a glob and a `[ -f ]` — builtins, no process. Past that the cost is one `stat` covering every wire
at once rather than one each, which is why 16 wires cost roughly what 4 do plus change. `jq` runs
only for a wire that actually grew, and the sidecar is rewritten only when an offset actually moved
— an idle render reads it and puts nothing back.

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

**The acquisition time is written in the same syscall, but not in the same instant.** The open comes
first, so between the two a contender can read a lock file that exists and says nothing yet. Reading
that empty stamp as zero — unset, therefore ancient, therefore dead — let the contender take the
lock from a holder a microsecond old, and the second write through the section overwrote the first.
It surfaces as a ring that never sounds and a few dollars the ear never counts — three runs in eight
of the ten-way drive under bash 3.2 in a container, none in eight after the fix, and rare enough on
a fast native shell to look like a fluke when it does happen. So an unreadable stamp means "wait",
and only a stamp still unreadable after the whole spin means "corpse". Anything that
reads a timestamp out of a file this way needs the same distinction; the numeric guards elsewhere in
this script default to zero on purpose and are safe because zero there means "not yet", not "long
ago".

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

`drive/matrix.sh` — every drive, on every platform this project claims. It is not a unit-test suite
and should not become one: each drive builds a whole scratch world, runs the real script against it
with real payloads on stdin, and checks what came out the other end. Nothing in `drive/` shares code
with `bin/rtc`; the figures the drives expect are computed a second time, from the rows, by a
different `awk`. The drives are here because the ones written for 2.6.0 lived in a session
scratchpad and were gone by the next session, and the version after that spent its first hour
rebuilding them from this file.

```
drive-kimi        the main wire and the subagent wires: adopt, price, partial lines, rotation,
                  per-model rates, and the sample the estimate is taught
drive-claude      the Claude side — the once-per-turn TTL read, the band hook, the halt
                  marker, doctor, and a setup/uninstall round trip
drive-ring        the cooldown, the lock, and the detached refresh
drive-rates       `rates` against a canned models.dev, including a subagent model that
                  config.toml has never heard of
drive-concurrent  ten sessions on one shared ring, and a subagent writing its wire while
                  renders land on it
drive-real        a real session off this machine, replayed from byte 0, then again with a
                  second real model on one of its subagents
```

The three platforms it runs them on are `native`, the macOS-shaped `PATH` from `drive/mkshim.sh`,
and bash 3.2.57 in a container — see the macOS constraint above for why both simulated halves are
worth the trouble. `drive/bench.sh` times idle renders, which is the number the performance section
below is about.

Two things the drives cannot reach, so they were driven by hand and are worth repeating by hand
after any change to the wire tailer. Watching a live Kimi session: `kimi -p '…'` in a scratch
directory with a one-second render loop pointed at the session it creates (`-p` refuses to combine
with `-y` or `--auto`; it needs neither). The wire of a subagent spawned mid-session appears between
two renders and is counted from byte 0, which is the rule that is easiest to get backwards.
And measuring Claude's rollup, which needs a live session with rtc in its statusline — see the
`total_cost_usd` constraint for the method.

Everything the drives do can also be done by hand. Synthetic payloads on stdin are all the script
needs — everything is in the JSON:

```bash
printf '{"session_id":"t","model":{"display_name":"Opus 5","id":"claude-opus-5"},"prompt_id":"p1",
"cost":{"total_cost_usd":10.00},"context_window":{"total_input_tokens":300000,
"context_window_size":1000000,"current_usage":{"cache_creation_input_tokens":900,
"cache_read_input_tokens":300000}}}' | RTC_MUTE=1 bin/rtc
```

Feed successive renders with rising `cost` to exercise the ring, the fade and sampling. Use a scratch
`session_id` and delete `$XDG_RUNTIME_DIR/rtc-<id>.*` between runs, or you will debug yesterday's
state. `XDG_CACHE_HOME` to a temp dir keeps a test from teaching the real model rate.

The Kimi drive is a snapshot plus a synthetic wire log — point `KIMI_CODE_HOME` at a scratch dir and
append `usage.record` rows between renders to make requests happen:

```bash
mkdir -p "$K/sessions/proj/session_t/agents/main"
SNAP='{"model":"K3","cwd":"/tmp","gitBranch":null,"permissionMode":"manual","planMode":false,
"contextUsage":0.05,"contextTokens":55000,"maxContextTokens":1048576,"sessionId":"session_t",
"version":"0.34.0"}'
printf '%s' "$SNAP" | KIMI_CODE_HOME="$K" RTC_MUTE=1 RTC_PRICE_kimi_code_k3="3 0.3 3 15" bin/rtc
printf '%s\n' '{"type":"usage.record","model":"kimi-code/k3","usage":{"inputOther":1207,
"output":537,"inputCacheRead":55000,"inputCacheCreation":0},"usageScope":"turn","time":1}' \
  >> "$K/sessions/proj/session_t/agents/main/wire.jsonl"   # then render again — a bump lands
```

Subagents are the same drive with `agents/agent-N/wire.jsonl` beside `agents/main/`. Every assertion
worth making about either kind of wire is in `drive-kimi` and `drive-real`, each one there because it
broke something on the way in — and the one to look at first if the estimate ever starts drifting is
that the `.turns` sample equals the **main** bump rather than the total, which is what catches
subagent money being fed to a figure that must not see it.

Real data beats synthetic, and `drive-real` finds its own: the session on this machine with the most
subagent wires, replayed from byte 0, against a `jq` sum over every row in every wire. On the 677-row
four-subagent session it picks here, $66.839405 both ways, $3.612000 of it the subagents'. Then it
takes a real wire from a session that ran a different model, drops it in as a subagent, and checks
that each row is priced by the model it names — real rows and real aliases in a topology no session
here has produced on its own, which is as close as a replay gets to the thing itself.

Time-dependent behaviour — fade, cache expiry — is tested by rewriting the timestamp in the state
file rather than sleeping. Rewrite it with `printf "%.6f"`; `awk`'s default output format turns an
epoch into `1.78648e+09` and the test silently stops meaning anything.

Cross-session behaviour cannot be tested that way, because the point of it is what several processes
do to one file at the same moment — `drive-concurrent` drives ten `session_id`s at once with `&` and
`wait`. Rings are counted by putting a player that records instead of playing first on `PATH`, named
after whichever one this platform would really have reached, so `play_sound` takes the branch it
takes in earnest; `lib.sh` builds it. `$50` across ten concurrent sessions at `RTC_THRESHOLD=5` must
give exactly ten rings with nothing carried anywhere afterwards — that assertion failed on the first
implementation of the shared ring, and failed again under a BSD userland for an unrelated reason.
Give the sessions an idle render or two before counting: a ring that lands on the
same instant as the last bump is delivered on the render after it.

## Releasing

```bash
./drive/matrix.sh            # all three platforms, ~90s — a Mac cannot be checked after the fact
# bump ALL THREE manifests — they are checked independently
sed -i 's/"version": "X"/"version": "Y"/' .claude-plugin/plugin.json .claude-plugin/marketplace.json kimi.plugin.json
git commit && git push
claude plugin marketplace update realtokencost
claude plugin uninstall realtokencost@realtokencost
claude plugin install realtokencost@realtokencost
"$(ls -d ~/.claude/plugins/cache/realtokencost/realtokencost/*/ | sort -V | tail -1)bin/rtc" setup
# kimi: /plugins install https://github.com/api-haus/realtokencost (reinstalls the managed copy),
# then setup from it the same way; /reload-tui picks up tui.toml without a restart
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
