# ZZ Linux Setup

ZZ Linux Setup is a modular, idempotent Linux post-install desktop bootstrapper for a minimal Niri + Noctalia v4 Shell desktop with GTK-oriented applications and GTK/Qt integration. Ghostty is the default terminal. `gum` provides the primary interactive wizard.

## Status

- Fedora is the supported target for v1.
- The design keeps Fedora-specific package-manager logic isolated so additional distros can be added later without rewriting common modules.

## Desktop Philosophy

- Niri is the compositor/session target.
- Noctalia v4 Shell is a shell layer, not a full desktop environment. Fedora installs it from Terra with the `noctalia-shell` package.
- GTK desktop defaults are the baseline:
  - Nautilus for file management
  - Neovim as the default handler for plain text and source files
  - Evince for PDFs and other document viewing
  - imv for lightweight image viewing
  - Satty-backed screenshots using the `grim` + `slurp` capture flow
  - GTK/GNOME portals, Noctalia's `polkit-agent` plugin, Adwaita GTK defaults, Yaru icons, and qtct integration
  - Noctalia's `gtk`, `qt`, and `kcolorscheme` templates drive GTK and Qt application color theming
- Ghostty is the default terminal.

## Session Model

- SDDM provides the graphical login and session chooser.
- Choose the `Niri` session at login.
- Noctalia is launched from Niri autostart with `spawn-at-startup "qs" "-c" "noctalia-shell"`.
- Noctalia ships with the Niri template pre-enabled through managed user settings.
- The default wallpaper is seeded to `~/Wallpapers/SilentPeaks.jpg`, Noctalia's wallpaper picker is pointed at `~/Wallpapers`, and `~/.cache/noctalia/wallpapers.json` selects it by default.
- Niri config and Noctalia templates/plugins are stowed from this repo. Noctalia's live `settings.json` is seeded into `~/.config/noctalia/settings.json` and then left as writable user state so GUI changes do not dirty the repo.
- When Visual Studio Code is selected, `~/.config/Code/User/settings.json` is also managed so the editor stays on `NoctaliaTheme`.
- `~/.config/noctalia/plugins.json` enables Noctalia's built-in `polkit-agent` plugin from the official plugin source, so no separate session polkit binary is launched from Niri.
- Noctalia template activation is plan-aware: GTK, Qt, and KColorScheme are always enabled; built-in templates are enabled for installed supported apps such as Niri, Ghostty, Starship, btop, Yazi, VS Code, Pywalfox, and Zen Browser; user templates are kept for repo-specific Neovim, Zsh syntax highlighting, and icon-theme integration.
- Noctalia v4 uses the existing JSON settings flow in `~/.config/noctalia/settings.json`; TOML settings/package handling for later Noctalia releases is intentionally out of scope.
- Firefox Noctalia theming uses Pywalfox. Fedora installs it globally with `sudo python3 -m pip install --upgrade pywalfox` and then registers the native messaging host for the target user.
- The installer never starts SDDM immediately. Reboot to begin using the graphical login.
- Selecting Visual Studio Code also enables Noctalia's built-in `code` template automatically. Fedora uses Microsoft's RPM repo.

## Bundle Model

- `BASE_BUNDLE_IDS_fedora` defines the non-optional base bundles.
- Base bundles are always planned and installed first. They are the protected desktop baseline, including Niri, Noctalia, SDDM, Zsh, Firefox, core services, portals, GTK/Qt integration, file integration, and managed base dotfiles.
- A base bundle failure is fatal because the result would not be a functioning desktop baseline.
- `DEFAULT_BUNDLE_IDS_fedora` defines broader default selections that are planned by default but installed after the base bundles.
- Wizard and `--select` choices add or override optional categories. Optional package/source/action failures warn and continue where possible so one broken optional component does not prevent the base desktop setup from completing.

## Shell Tooling

- The base install always includes Zsh and its managed config.
- The wizard exposes a `Shell / CLI tools` category for terminal utilities and prompt tooling.
- Current choices include `zsh`, `starship`, `zoxide`, `fastfetch`, `gh`, `btop`, `fd`, `fzf`, `bat`, and `yazi`.
- The Starship prompt uses a managed static config and Noctalia's built-in `starship` template injects the active theme palette.
- Zsh setup bootstraps Oh My Zsh, installs the managed `~/.zshrc`, and changes the target user's login shell to `/bin/zsh`.
- `doctor` checks the selected shell tools and their managed config files when they are present in the saved plan.

## Install

Remote install:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-linux-setup/main/bootstrap.sh | bash -s -- --ref main
```

This clones the repo to `~/zz-linux-setup` by default before launching the installer.

Pinned install:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-linux-setup/main/bootstrap.sh | bash -s -- --ref v0.1.0
```

Local install:

```bash
git clone https://github.com/bgmulinari/zz-linux-setup.git
cd zz-linux-setup
./install.sh wizard
```

Non-interactive install:

```bash
./install.sh install --yes --select browser=firefox,brave --select dev=vscode,neovim --select shell=zsh,starship,gh,fzf
```

Supported commands:

```bash
./install.sh wizard
./install.sh install --yes
./install.sh install --dry-run
./install.sh install --use-saved
./install.sh print-plan
./install.sh print-plan --format json
./install.sh check
./install.sh doctor
./install.sh list-profiles
./install.sh list-choices
./install.sh list-sources
```

`check` is read-only. It accepts the same selection flags as `install` and `print-plan`, builds the plan, and reports readiness, source status, service status, managed-config conflicts, and key command availability without enabling repos, installing packages, or changing dotfiles.

## Idempotency

The project is intended to be safe to re-run after repository updates.

Managed items:

- package sources and repositories
- package installation
- Flatpak remotes and apps
- base bundle installation before optional bundle installation
- system services
- SDDM enablement
- managed dotfiles through `stow --restow`
- managed dotfile conflict previews before Stow moves or backs up existing files
- modular Niri config under `~/.config/niri/cfg/`
- MIME defaults and selected post-actions

Re-running should:

- install newly selected packages
- update managed files only when content changes
- re-enable required services if needed
- avoid duplicate repos, remotes, services, and stow entries

## Not Managed

- disk partitioning
- user creation
- Secure Boot setup
- automatic reboot
- starting SDDM immediately
- full desktop environment installation
- immutable Fedora Atomic support
- Debian, openSUSE, or NixOS support in v1

## Third-Party Source Warnings

- Fedora COPRs are optional or required depending on the base and selected component set. Review them before enabling.
- RPM Fusion is part of Fedora's default selections because codecs and Steam are default-selected, but it is not part of the protected base desktop baseline.
- Flathub is part of the default selections when default Flatpak apps are planned, but it is not part of the protected base desktop baseline.
- Selecting `zsh` also fetches Oh My Zsh plus the `zsh-autosuggestions` and `zsh-syntax-highlighting` plugin repositories from GitHub.

## How To Extend

Add a package:

1. Put the package name in the appropriate Fedora/source manifest under `packages/fedora/`.
2. Reference that manifest from a bundle descriptor.
3. Add the bundle to `BASE_BUNDLE_IDS_fedora` only if it is required for the non-optional functioning desktop baseline. Otherwise expose it through `DEFAULT_BUNDLE_IDS_fedora` or a choice file.

Add a source:

1. Add a `.source` descriptor under `sources/fedora/`.
2. Teach the Fedora adapter how to enable it if it is a new source kind.
3. Reference the source ID from a bundle descriptor.
4. Mark sources required only when a base bundle depends on them.

Add a wizard choice:

1. Add or update the relevant `choices/fedora/*.conf` TSV.
2. Ensure referenced sources and manifests exist.
3. The planner will include it in `list-choices`, validation, and plan generation.

Add another distro:

1. Add `distros/newdistro.sh`.
2. Add `sources/newdistro/`.
3. Add `packages/newdistro/`.
4. Add `choices/newdistro/`.
5. Define `BASE_BUNDLE_IDS_newdistro` for the non-optional desktop baseline and `DEFAULT_BUNDLE_IDS_newdistro` for broader default selections.

The common modules should not need changes for a straightforward new adapter.

## Tests

Logs default to `$XDG_STATE_HOME/zz-linux-setup/logs` or `~/.local/state/zz-linux-setup/logs`. Set `LOG_DIR` to override the location.

Run:

```bash
./tests/smoke.sh
```

That covers shell syntax, parser tests, distro detection, planner expectations, idempotency helper behavior, and the Fedora base-bundles-first install invariant.
