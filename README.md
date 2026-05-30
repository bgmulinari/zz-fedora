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
- Ghostty is the default terminal. The installer enables Ghostty's user systemd service on first login, keeps the background process running, and uses `ghostty +new-window` for Niri/Noctalia terminal launches.

## Session Model

- SDDM provides the graphical login and session chooser.
- Choose the `Niri` session at login.
- Noctalia is launched from Niri autostart with `spawn-at-startup "qs" "-c" "noctalia-shell"`, and Niri's terminal keybinding opens Ghostty through `ghostty +new-window`.
- Noctalia ships with the Niri template pre-enabled through managed user settings.
- Bundled wallpapers are seeded to `~/Wallpapers`, Noctalia's wallpaper picker is pointed there, and `~/.cache/noctalia/wallpapers.json` selects `BlueTide.jpg` by default.
- Niri config and Noctalia user templates are stowed from this repo. Noctalia's live `settings.json` and `plugins.json` are seeded into `~/.config/noctalia/` and then left as writable user state so GUI changes do not dirty the repo.
- When Visual Studio Code is selected, `~/.config/Code/User/settings.json` is also managed so the editor stays on `NoctaliaTheme`.
- `~/.config/noctalia/plugins.json` enables Noctalia's built-in `polkit-agent` plugin from the official plugin source, so no separate session polkit binary is launched from Niri.
- Noctalia template activation is plan-aware: GTK, Qt, and KColorScheme are always enabled; built-in templates are enabled for installed supported apps such as Niri, Ghostty, Starship, btop, Yazi, VS Code, Pywalfox, and Zen Browser; user templates are kept for repo-specific Neovim, Zsh syntax highlighting, and icon-theme integration.
- Noctalia v4 uses the existing JSON settings flow in `~/.config/noctalia/settings.json`; TOML settings/package handling for later Noctalia releases is intentionally out of scope.
- Firefox Noctalia theming uses Pywalfox. Fedora installs it globally with `sudo python3 -m pip install --upgrade pywalfox` and then registers the native messaging host for the target user.
- The installer never starts SDDM immediately. When no display manager is already enabled, reboot to begin using the graphical login.
- Selecting Visual Studio Code also enables Noctalia's built-in `code` template automatically. Fedora uses Microsoft's RPM repo.

## Bundle Model

- `BASE_BUNDLE_IDS_fedora` defines the non-optional base bundles.
- Base bundles are always planned and installed first. They are the protected desktop baseline, including Niri, Noctalia, SDDM when no display manager is already enabled, Zsh, Firefox, core services, portals, GTK/Qt integration, project-managed fonts, shell tooling, file integration, and managed base dotfiles.
- A base bundle failure is fatal because the result would not be a functioning desktop baseline.
- `DEFAULT_BUNDLE_IDS_fedora` is intentionally empty while the base desktop is being hardened. AI, development, .NET, office, gaming, media, and extra browser bundles are opt-in.
- Wizard and `--select` choices add optional categories. Optional package/source/action failures warn and continue where possible so one broken optional component does not prevent the base desktop setup from completing.
- Each generated plan writes `base-rationale.tsv` under the plan directory so required base package, action, Flatpak runtime, and source ownership is explicit. The report includes a responsibility class, consumer, and reason for each base item.
- Each generated plan writes `files/managed-config-policy.tsv` so planned config paths are visible as `stow`, `seed-if-missing`, `first-run`, or `generated`, with the conflict behavior shown before install.

## Shell Tooling

- The base install always includes Zsh and its managed config.
- The base install always includes Zsh, Oh My Zsh setup, Starship, zoxide, fastfetch, `gh`, btop, fd, fzf, bat, Yazi, and their managed dotfiles.
- The Starship prompt uses a managed static config and Noctalia's built-in `starship` template injects the active theme palette.
- Zsh setup bootstraps Oh My Zsh, installs the managed `~/.zshrc`, and changes the target user's login shell to `/bin/zsh`.
- `doctor` checks the selected shell tools and their managed config files when they are present in the saved plan.

## Install

Remote install:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-linux-setup/main/bootstrap.sh | bash -s -- --ref main
```

This prints the bootstrap packages it will install, asks for confirmation, clones the repo to `~/zz-linux-setup` by default, and then launches the installer.

Pinned install:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-linux-setup/main/bootstrap.sh | bash -s -- --ref v0.1.0
```

Unattended dry-run bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-linux-setup/main/bootstrap.sh | bash -s -- --yes --dry-run --ref main
```

Clone to a custom directory:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-linux-setup/main/bootstrap.sh | bash -s -- --dir "$HOME/src/zz-linux-setup" --ref main
```

Local install:

```bash
git clone https://github.com/bgmulinari/zz-linux-setup.git
cd zz-linux-setup
./install.sh wizard
```

Non-interactive install:

```bash
./install.sh install --yes
./install.sh install --yes --select browser=brave --select dev=vscode,neovim
```

Supported commands:

```bash
zz doctor
zz logs --tail
zz debug
zz first-run
zz defaults
zz update all
zz commands --json
./install.sh wizard
./install.sh install --yes
./install.sh install --dry-run
./install.sh install --preview-commands
./install.sh install --use-saved
./install.sh print-plan
./install.sh print-plan --format json
./install.sh check
./install.sh doctor
./install.sh first-run
./install.sh defaults
./install.sh list-profiles
./install.sh list-choices
./install.sh list-sources
```

`check` is read-only. It accepts the same selection flags as `install` and `print-plan`, builds the plan, and reports readiness, source trust policy, service status, managed-config conflicts, managed-config policy, and key command availability without enabling repos, installing packages, or changing dotfiles.

`--preview-commands` prints each command before running it and asks for confirmation in an interactive terminal. Use it with `install` when debugging a live run. `--yes --preview-commands` prints the commands without stopping for each confirmation.

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
- RPM Fusion is part of the protected Fedora base source set so appstream metadata and RPM Fusion packages are available before optional package planning.
- Flathub is part of the protected Fedora base source set because the base plan installs GTK Flatpak theme runtimes and optional Flatpak apps use the same remote.
- Terra is a required base source for Noctalia Shell and Ghostty. Its generated source-trust line is marked as an explicit bootstrap exception.
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

The test suite uses Bats. On Fedora, install the runner with:

```bash
sudo dnf install bats
```

Run:

```bash
./tests/smoke.sh
```

That is the required fast PR gate. It covers shell syntax, manifest parsing, catalog validation, distro detection, fast planner behavior, and CLI smoke checks. It does not run `shellcheck` unless `ZZ_TEST_LINT=1` is set.

Run the full regression suite with:

```bash
./tests/full.sh
./tests/full.sh --timings
./tests/profile.sh
```

`tests/full.sh` runs all Bats suites and `shellcheck` when available. `tests/profile.sh` prints suite timings and fails when a Bats file exceeds `ZZ_TEST_PROFILE_THRESHOLD`, defaulting to 15 seconds.
