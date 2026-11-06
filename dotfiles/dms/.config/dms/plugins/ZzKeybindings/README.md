# Keyboard Shortcuts

Every Niri keyboard shortcut in one list. Press Super+/ or Super+K and it opens centered on
the screen, like the launcher: each row is a chord drawn as keycaps and
what it does, the ones you use most first. Type to search by name or by
chord; the search is fzf, so `clwin` finds Close window, `'vol` wants the
exact text, `^open` a start, `!move` rules rows out, and a chord typed in
full (`super shift s`) goes to the top. Enter, or a click, runs the
bind as if you had pressed it; Ctrl+E opens Settings > Keyboard Shortcuts
to change binds. Arrow keys (or Ctrl+N/P, Ctrl+J/K) move, Escape clears
the search and then closes.

The list is read from the live Niri configuration on every open, through
`dms keybinds show niri`, so a bind you add anywhere in the Niri config
shows up the next time. A bind is named by its `hotkey-overlay-title`;
one without a title gets a name from its action or media key, and
`hotkey-overlay-title=null` hides it, as it would in Niri's own hotkey
overlay, which this list replaces. A second chord for the same action
shares the first one's row.

## Files

| File | Role |
|---|---|
| `ZzKeybindings.qml` | The daemon: loads the rows, hosts the modal, runs a picked bind |
| `ZzKeybindingsPanel.qml` | The list: fzf search, keycaps, keyboard and pointer |
| `scripts/zz-keybindings` | Turns `dms keybinds show niri` into ranked rows with `niri msg action` commands; `--print` prints them as text |

## Shell IPC

```bash
dms ipc call plugins toggle zzKeybindings   # the list (Super+/, Super+K)
```

The binds live in `~/.config/niri/dms/binds.kdl`, seeded once; an older
file needs them added (Settings > Keyboard Shortcuts) or
`zz refresh niri/dms/binds.kdl`.

Dependencies: `python3` (the rows are built with `/usr/bin/python3`),
`fzf` (the search, part of every ZZ install), and `niri` (a picked row runs
through `niri msg action`).
