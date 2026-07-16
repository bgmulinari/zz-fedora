# Niri Outputs plugin guidance

## Scope and architecture

- Keep `panel.luau`, `widget.luau`, and `shortcut.luau` focused on native Noctalia UI and user interaction.
- Keep Niri config switching, KDL generation, validation, persistence, and timeout logic in `backend.py`.
- Do not add an always-running plugin service or poll Niri in the background. Query outputs when the panel opens, when the user refreshes or resets it, and after keep or restore completes.
- The watchdog may run only while an output preview is awaiting confirmation. It must terminate after keep, revert, or successful timeout restoration.

## Safety contracts

- Preview must leave the normal Niri configuration untouched. Render the draft into a temporary output include,
  create a temporary copy beside the normal top-level config, replace only the managed
  `include "./cfg/display.kdl"` line, and switch Niri to that temporary top-level config once. The active preview must
  not include or watch the persistent output file.
- Revert and timeout switch Niri back to the normal top-level config once. Do not replay individual output settings
  through `niri msg output`.
- Keep copies the already validated temporary output include into the dedicated persistent file, creates a
  `.previous` backup when that file exists, and switches Niri back to the normal top-level config.
- The plugin owns the complete dedicated `display.kdl` file and replaces it from the connected outputs shown in the
  panel. Keep generated output state and preview files out of the repository.
- Never allow every connected output to be disabled.
- Wait for Niri's successful `ConfigLoaded` event before reporting any config switch as complete.
- Never commit generated `display.kdl`, connected-output details, preview tokens, or other hardware-specific state.

## UI conventions

- When upstream reference checkouts are available, use the Noctalia source for native controls and patterns, the Noctalia documentation for plugin APIs, and the Niri source for output semantics. Do not assume a fixed checkout location.
- Match Noctalia capitalization, spacing, button variants, and compact settings-row layouts.
- Write help text as sentence fragments without a trailing period.
- Keep plugin-owned UI copy and backend error grammar in `translations/en.json`, use `noctalia.tr()` or
  `noctalia.trp()` from Luau, and leave connector names, modes, file paths, and other runtime values untranslated.
- Enable Preview and Reset only when the draft differs semantically from the queried output state. Enable Keep Changes during an active preview, including after the panel is reopened.
- Keep the detail area scrollable so smaller screens remain usable.

## Verification

Run focused checks from the repository root after behavior changes:

```bash
noctalia plugins lint dotfiles/noctalia/.local/share/noctalia/plugins/niri-outputs
bats tests/noctalia_niri_outputs_plugin.bats
python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("dotfiles/noctalia/.local/share/noctalia/plugins/niri-outputs/backend.py").read_text())'
noctalia config validate
git diff --check
```

For copy-only capitalization or punctuation changes, run the lint and existing focused tests; do not add a new regression test solely for the text change.

Before committing broader changes, also run:

```bash
./tests/smoke.sh
./tests/full.sh
```

Work is complete only when the focused checks pass, no generated cache or hardware-state files are staged, and Preview never writes the persistent output file.
