# Agent Usage

One bar pill and one popout for the AI agent subscriptions on the machine:
Claude Code, Codex, and OpenCode. The pill shows the fullest rate-limit window
as a percentage, or the agent and window pinned in the settings, and turns red
at 90%. The popout is one page, limits first:

- **Hero**: a line that rotates through what the token counts add up to across
  every agent (tokens this week and today, the most used model, the busiest
  day, today's prompts and sessions), and a refresh button.
- **Mascots**: a strip under the hero with Clawd for Claude Code and the Codex
  companion for Codex, each following its own agent and drawn as its own product
  draws it. An agent with no mascot (OpenCode) adds none.
  - Clawd uses Claude Code's glyphs, poses, and 60ms sequences. Eyes shut and
    crouched when no session runs, its look-around loop when one is idle, its
    waddle from edge to edge with a turn at each end while one works, its jump
    when one waits for you, and hiding and peeking when a limit is used up. It
    celebrates when a turn ends or a window resets, and a click plays one of the
    sequences a click plays in Claude Code.
  - The companion uses the ChatGPT app's sheet, timings, and rules. Its idle loop,
    its laptop while a session log is being written, its waiting row at 90% of a
    window, and its failed row when a limit is used up. It jumps on hover or when
    a window resets, and waves on a click. Codex publishes no session states, so "working" is inferred from
    those writes, and these status rows keep looping where the app settles back to
    idle, since the strip is only on screen for a glance.
  - Each makes a random entrance when the popout opens and breaks into something
    else every 6 to 14 seconds, whatever it is doing, unless it is asleep or out
    of its limit. That includes props either can play with, drawn by this plugin:
    juggling, thinking, dozing, headphones, confetti, a bright idea, coffee,
    bubbles, and seeing stars. The companion also turns its head right round, from
    its sheet's two look rows when the sheet has them.
  - Together, they get up to something every 10 to 20 seconds, picked to suit what
    each agent is doing: a high five, a chase, hide and seek, copycat, a game of
    catch, a jam, or a party while idle; the companion waking Clawd; Clawd checking
    on the laptop; cheering each other up at a limit. They notice each other's
    clicks and celebrate together, and a mood change ends a duet at once so the
    strip stays truthful. Their bodies use official frames; the choreography and
    props are the strip's own.
  - They animate only while the popout is open, hold still when the shell's
    animations are off, and have a toggle in the settings.

- **One section per subscription**: an agent with limits or a plan gets one;
  local history alone only feeds the hero's line. Its mark, name, and plan,
  then a compact line per limit window with its meter, the percentage used,
  and the time until it resets. A model-scoped allowance on the same
  clock (Claude's Fable weekly limit) is a tick on that window's meter, named
  in the row's tooltip. A lapsed or missing sign-in shows a _Sign-in required_
  link that signs in again from a terminal. Any other trouble leaves the last
  known limits on show, with a small info mark beside the name whose tooltip
  says why they are not current; each meter's tooltip says how old it is.

The widget is strictly a display. `scripts/update-usage` runs one
`scripts/collect-<agent>` collector per agent and writes each record to
`~/.local/state/zz-fedora/agent-usage/<agent>.json`; `UsageModel.qml`
discovers and watches those records; `AgentUsageWidget.qml` draws them.
Adding an agent means adding a collector that prints the same record shape
(the shared pieces live in `scripts/usage_common.py`), a toggle in
`Settings.qml` plus its id in `collectorIds`, and a mark at
`assets/<agent>.svg` (with an `assets/<agent>-light.svg` twin when the mark
is drawn in white); a missing mark falls back to a generic glyph.

| Collector | Limits | Local stats |
|---|---|---|
| `claude` | Anthropic's OAuth usage endpoint (5-hour session, 7-day weekly, and any model-scoped windows), through the signed-in CLI's token | `~/.claude/projects` transcripts, pi/omp and opencode sessions on an Anthropic provider, plus `stats-cache.json` and `history.jsonl` as fallbacks |
| `codex` | The Codex app-server RPC: every bucket, an individual spend cap, and free reset credits | native Codex CLI session files touched in the last 30 days, plus pi/omp sessions on `openai-codex` and opencode sessions on `openai` |
| `opencode` | OpenCode Go's usage endpoint (rolling, weekly, monthly); a key without a Go plan shows local usage alone | pi/omp and opencode sessions on the Zen and Go providers |

Tokens are counted once, under the provider that bills them: pi, omp, and
opencode sessions are split by provider, and Claude Code or Codex sent to
another provider's API or a server you run counts under neither. A prompt is
one a person typed, never a model request.

Limits follow the same rules for every agent: each credential keeps its own
last answer under `~/.cache/zz-fedora/agent-usage/`, so another sign-in never
shows this one's numbers. An answer stands in for a probe for 15 seconds unless
refresh is pressed. A failed check keeps the last answer, with its age on hover
and windows that have since reset back at zero. An endpoint that cannot be
reached is retried soon. An access token only the agent's own CLI renews reads
_Limits paused_; a refused or lapsed sign-in reads _Sign-in expired_. A
non-default home is honored via `CLAUDE_CONFIG_DIR` and `CODEX_HOME`, and
OpenCode's database via `OPENCODE_DB`.

An agent appears only when it is enabled in the plugin settings and has
recorded usage, locally or on a synced machine. With nothing to report the
pill collapses out of the bar, which is why the widget ships in the default
bar layout: a machine that never ran an AI agent draws nothing.

## Interactions

- Left click opens the popout (Esc or a click outside closes it); right click
  on the pill forces a full refresh, as do the refresh button and `r`.
- The arrows (or `j`/`k`) walk a cursor over everything that does something;
  hovering moves the same cursor, and Enter acts on it, or refreshes when
  nothing is lit.
- The terminal button on a section starts that agent through `zz agent run`.
- Ctrl+Up/Down (or Ctrl+`k`/`j`) moves the agent the cursor is in up or down the
  page, and dragging an agent by its mark does the same. The order is kept in
  `~/.local/state/zz-fedora/agent-usage-order.json`.
- The popout refreshes the rate limits every time it opens and regenerates
  every record on the configured interval (15 minutes by default).

## Settings

Settings > Plugins > Agent Usage: enable or disable each agent, pin the bar to
one agent or kind of window (an agent without the pinned window shows its
fullest, and one without limits leaves the bar to the fullest anywhere), set the
refresh interval, and optionally merge usage snapshots from other machines
through a synced folder. Rate limits stay per-account and are never merged.

Dependencies: `python3` (the collectors run with `/usr/bin/python3`). `rg`, when
installed, reads pi and omp sessions; without it they are skipped.

The Codex companion's spritesheet is not shipped here. `scripts/codex-pet` copies
the newest one out of the installed ChatGPT app into
`~/.cache/zz-fedora/agent-usage/`, or else reuses the copy Codex keeps under
`~/.codex/cache/tui-pets`, or else fetches it once from the public CDN Codex uses,
sending no credentials. If there is none, the strip simply goes without that
mascot.
