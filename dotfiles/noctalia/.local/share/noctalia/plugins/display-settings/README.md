# Display Settings

This local Noctalia v5 plugin provides a native Niri output configuration panel.

- The bar widget and optional Control Center shortcut open the panel.
- The panel reads live output state from `niri msg -j outputs` only when opened, refreshed, or reset.
- Preview uses temporary `niri msg output` changes and an external rollback watchdog.
- Keep validates and atomically replaces `~/.config/niri/cfg/display.kdl`, which the managed Niri configuration
  includes directly.
- Persistent reloads remain pending until Niri reports a successful `ConfigLoaded` event. Backend errors include the
  authoritative preview state so the panel keeps rollback controls active whenever restoration still needs retrying.
- If the confirmation countdown cannot be armed after applying a preview, the backend immediately restores the
  persistent configuration instead of leaving the temporary layout under the longer crash guard.
- Existing output files are replaced only when every active setting can be represented by the plugin. Advanced Niri
  settings such as modelines, VRR on-demand, `max-bpc`, hot corners, or per-output layout are left untouched and block
  Preview with an explanation rather than being silently discarded. Saved settings also remain untouched when an
  output is disabled only in Niri's transient IPC configuration and its inactive values cannot be queried.

The persistent target is `~/.config/niri/cfg/display.kdl`. The file is hardware-specific and must not be copied
between machines. A `.previous` backup is created before an existing configuration is replaced.
