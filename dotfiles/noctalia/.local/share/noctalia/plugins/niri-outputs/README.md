# Niri Outputs

This local Noctalia v5 plugin provides a native Niri output configuration panel.

- The panel reads connected outputs from `niri msg -j outputs` when opened, refreshed, reset, or reconciled after keep or restore.
- Preview renders the draft to a temporary output file under `$XDG_RUNTIME_DIR`. A temporary top-level config beside
  `~/.config/niri/config.kdl` copies the normal config but replaces its managed `display.kdl` include with that
  temporary file, then Niri switches to it with one `load-config-file --path` action. Keeping the temporary config
  beside the normal one preserves all other relative includes without watching the persistent output file.
- Revert and the confirmation timeout switch Niri back to the normal top-level config with one action. The persistent
  output file is never modified by Preview, so restarting Niri or rebooting naturally returns to the normal config.
- Keep copies the already validated temporary output file to `~/.config/niri/cfg/display.kdl`, backs up an existing
  file as `display.kdl.previous`, and switches Niri back to the normal config.
- A detached watchdog exists only while a preview is active, so previews still expire after the panel closes.
- Each config switch waits for Niri's `ConfigLoaded` event before the backend reports success.
- The plugin owns the complete `display.kdl` file and writes the connected outputs represented by the panel. Generated
  output files are hardware-specific local state and must not be committed.
- Static UI copy and backend errors resolve through `translations/en.json`. Connector names, modes, paths, and command
  details remain untranslated runtime values.

This design intentionally does not use per-output `niri msg output` commands or replay captured output snapshots.
