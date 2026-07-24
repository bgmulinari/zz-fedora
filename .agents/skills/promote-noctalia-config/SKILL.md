---
name: promote-noctalia-config
description: Inspect Noctalia v5 Settings UI overrides and promote portable changes into this repo's product-owned default. Use when working in zz-fedora on Noctalia config, when the user asks what changed in the Noctalia UI, wants UI settings made default, wants overrides reset, or wants to avoid committing generated hardware-specific Noctalia state.
---

# Promote Noctalia Config

## Core Model

Noctalia v5 loads config in this order:

1. Built-in defaults
2. `~/.config/noctalia/*.toml`
3. `~/.local/state/noctalia/settings.toml`

In this repo, the product baseline is `dotfiles/noctalia/.config/noctalia/config.toml`. The user-owned `~/.config/noctalia/config.toml` entrypoint includes that live file from `~/.zz`, then includes `~/.config/noctalia/conf.d` for hand-written overrides. Noctalia Settings UI changes are written to `~/.local/state/noctalia/settings.toml`; that file wins only for keys it contains.

Do not make `settings.toml` product-owned. It may contain generated, host-specific state such as lockscreen widget output names and coordinates.

## Workflow

1. Inspect the current override state:

   ```bash
   python3 .agents/skills/promote-noctalia-config/scripts/noctalia_override_report.py
   ```

   The default report summarizes hardware/local state without printing all keys. Use `--show-local` only when debugging generated state.

2. Check for direct writes into product-owned repo files:

   ```bash
   git status --short
   git diff -- dotfiles/noctalia dotfiles/niri docs/design/noctalia-v5-integration-status.md
   ```

   Direct repo changes may be unrelated user edits. Do not attribute them to Noctalia unless there is direct evidence. Treat them as separate from `settings.toml` overrides and confirm whether they should be kept.

3. Classify changes:
   - `Overrides product default`: same key exists in the product config and state with different values. Usually a user preference candidate.
   - `State-only portable candidates`: key exists only in state. Promote only if it is clearly a portable preference.
   - `Hardware/local state`: generated or host-specific data. It is excluded from promotion candidates; do not repeat individual keys unless the user is debugging local state.
   - `Direct product config changes`: changed files already visible in git. Do not assume cause; keep only user-confirmed, intentional changes.

4. Promote only portable, intended preferences into `dotfiles/noctalia/.config/noctalia/config.toml`.

5. Remove the promoted keys from `~/.local/state/noctalia/settings.toml` so the product default becomes the source of truth again. Leave unpromoted local/hardware sections untouched.

6. Validate and show the result:

   ```bash
   noctalia config validate
   noctalia config export | sed -n '1,220p'
   git diff -- dotfiles/noctalia/.config/noctalia/config.toml docs/design/noctalia-v5-integration-status.md
   ```

7. Update `docs/design/noctalia-v5-integration-status.md` whenever the managed Noctalia baseline changes.

Do not commit unless the user asks.

## Promotion Rules

Safe promotion candidates usually include:

- `[theme]`
- `[theme.templates]`
- Shell UI preferences that do not encode machine details
- Wallpaper directories or default wallpapers that use portable paths like `~/Wallpapers`

Do not promote by default:

- `[lockscreen_widgets]`
- `[desktop_widgets]` placement/layout state
- Keys containing output names, monitor selectors, geometry, coordinates, or per-monitor tables
- Account credentials, OAuth tokens, plugin caches, downloaded catalogs, or runtime usage state

When unsure, ask or leave the key in `settings.toml`.

## Noctalia Docs

Use `~/repos/noctalia-docs/src/content/docs/v5/configuration/index.mdx` as the source of truth for config load order, state override behavior, exports, includes, and validation.
