# Display settings plugin guidance

## Scope and architecture

- Keep `panel.luau`, `widget.luau`, and `shortcut.luau` focused on native Noctalia UI and user interaction.
- Keep Niri IPC, KDL generation, validation, persistence, and rollback logic in `backend.py`.
- Do not add an always-running plugin service or poll Niri in the background. Query outputs when the panel opens or when the user explicitly refreshes or resets it.
- The rollback watchdog may run only while a display preview is awaiting confirmation. It must terminate after keep, revert, or successful timeout restoration.

## Safety contracts

- Treat display changes as a transaction: Preview applies temporary IPC changes, Keep persists validated KDL, and Revert or timeout restores the persistent configuration.
- Never allow every connected output to be disabled.
- Preserve settings that cannot be represented losslessly. Refuse to overwrite advanced or unknown Niri output configuration with a clear error.
- Wait for Niri's successful `ConfigLoaded` event before reporting a persistent reload as complete.
- Never commit generated `display.kdl`, connected-output details, preview tokens, or other hardware-specific state.

## UI conventions

- When upstream reference checkouts are available, use the Noctalia source for native controls and patterns, the Noctalia documentation for plugin APIs, and the Niri source for output semantics. Do not assume a fixed checkout location.
- Match Noctalia capitalization, spacing, button variants, and compact settings-row layouts.
- Write help text as sentence fragments without a trailing period.
- Enable Preview and Reset only when the draft differs semantically from the queried output state. Enable Keep Settings only during an active preview with unapplied changes.
- Keep the detail area scrollable so smaller displays remain usable.

## Verification

Run focused checks from the repository root after behavior changes:

```bash
noctalia plugins lint dotfiles/noctalia/.local/share/noctalia/plugins/display-settings
bats tests/noctalia_display_plugin.bats
python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("dotfiles/noctalia/.local/share/noctalia/plugins/display-settings/backend.py").read_text())'
noctalia config validate
git diff --check
```

For copy-only capitalization or punctuation changes, run the lint and existing focused tests; do not add a new regression test solely for the text change.

Before committing broader changes, also run:

```bash
./tests/smoke.sh
./tests/full.sh
```

Work is complete only when the focused checks pass, no generated cache or hardware-state files are staged, and the preview rollback path remains intact.
