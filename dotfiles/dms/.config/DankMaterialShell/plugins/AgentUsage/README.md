# Agent Usage

One bar pill and one popout for the coding-agent subscriptions on the
machine: Claude Code and Codex. The pill shows the fullest rate-limit window
as a percentage and turns red at 90%; the popout shows every limit with its
reset countdown, tokens per day for the last week, and the all-time token
split by model.

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
| `claude` | Anthropic's OAuth usage endpoint (5-hour session + 7-day weekly), through the signed-in CLI's token | `~/.claude/projects` transcripts, opencode sessions on an Anthropic provider, plus `stats-cache.json` and `history.jsonl` as fallbacks |
| `codex` | The Codex app-server RPC | native Codex CLI session files touched in the last 30 days, plus pi and opencode sessions on OpenAI |

Claude limits need a signed-in CLI; without credentials the popout says so
and shows local stats only. A non-default Claude directory is honored via
`CLAUDE_CONFIG_DIR`, Codex via `CODEX_HOME`. Collector caches live under
`~/.cache/zz-fedora/agent-usage/`: the local scans (reused briefly, and for
up to 15 minutes when only limits are wanted) and each agent's last probed
limits, which stand in for a failed probe until their windows reset.

An agent appears only when it is enabled in the plugin settings and has
recorded usage, locally or on a synced machine. With nothing to report the
pill collapses out of the bar, which is why the widget ships in the default
bar layout: a machine that never ran a coding agent draws nothing.

## Interactions

- Left click opens the popout (Esc or a click outside closes it); right
  click on the pill, or the refresh button beside the provider name, forces
  a full refresh.
- The popout refreshes the rate limits every time it opens and regenerates
  every record on the configured interval (15 minutes by default).

## Settings

Settings > Plugins > Agent Usage: enable or disable each agent, set the
refresh interval, and optionally merge usage snapshots from other machines
through a synced folder. Rate limits stay per-account and are never merged.

Dependencies: `python3` (the collectors run with `/usr/bin/python3`).
