# ZZ Fedora

ZZ Fedora is a modular, idempotent Fedora post-install desktop bootstrapper for a minimal Niri + Noctalia v5 desktop shell with GTK-oriented applications and GTK/Qt integration. Ghostty is the default terminal. `gum` provides the primary interactive wizard.

## Status

- Fedora Linux is the only supported platform. The installer validates that invariant before planning or applying changes.
- Catalog paths and installer internals intentionally avoid multi-distro indirection; Fedora package and source behavior lives in `lib/fedora.sh`.
- Noctalia v5 support is experimental while v5 is in beta; track checkpoints in `docs/noctalia-v5-integration-status.md`.

## Desktop Philosophy

- Niri is the compositor/session target.
- Noctalia v5 is a native Wayland shell layer, not a full desktop environment. Fedora installs the official `noctalia` package, allowing the current beta from Updates Testing when needed.
- The full desktop app profile installs GTK desktop defaults:
  - Nautilus for file management
  - GNOME Text Editor for desktop plain-text file handling
  - Papers for PDFs and other document viewing
  - Loupe for image viewing
  - Showtime and Decibels for local video and audio playback
  - GNOME utilities for calendar, clocks, contacts, fonts, logs, disks, scanning, camera, system monitoring, disk usage, virtual machines, and remote connections
  - Noctalia v5 screenshots through `noctalia msg screenshot-region`
  - GTK/GNOME portals, Adwaita GTK defaults, Yaru icons, and qtct integration
- Ghostty is the default terminal. The installer enables Ghostty's user systemd service on first login, keeps the background process running, and uses `ghostty +new-window` for Niri/Noctalia terminal launches.

## Session Model

- Noctalia Greeter provides the graphical login and session chooser through greetd when no display manager is already enabled.
- Choose the `Niri` session at login.
- Noctalia is launched from Niri autostart with `spawn-at-startup "noctalia"`, and Niri shell keybindings call `noctalia msg ...`.
- Noctalia v5 uses the managed `~/.config/noctalia/config.toml` baseline; GUI-managed overrides live in `~/.local/state/noctalia/settings.toml`.
- Bundled wallpapers are seeded to `~/.local/share/backgrounds`, and Noctalia defaults to the bundled `BlueTide.jpg`.
- Niri config is stowed from this repo. Hardware-specific Niri display config and `~/.config/niri/noctalia.kdl` are seeded only when absent.
- Noctalia template selection is managed through the curated config; generated runtime state and hardware-specific widget placement stay app-managed.
- The installer never starts greetd immediately. When no display manager is already enabled, reboot to begin using Noctalia Greeter.
- On systems that already have a full GNOME/KDE/Plasma desktop, the installer can use the minimal desktop app profile. This keeps Niri, Noctalia, Ghostty, shell tooling, and Niri support packages, while skipping replacement desktop apps, GTK/GNOME portal fill-ins, GTK/Qt look packages, and base media/source enablement that are only needed for the complete GTK-oriented baseline.

## Bundle Model

- `BASE_BUNDLE_IDS` defines the non-optional base bundles.
- Base bundles are planned and installed first after applying `--desktop-app-profile`. The full profile is the protected desktop baseline, including Niri, Noctalia, Noctalia Greeter through greetd when no display manager is already enabled, Zsh, core services, portals, GTK/Qt integration, project-managed fonts, shell tooling, file integration, and managed base dotfiles.
- `--desktop-app-profile auto|full|minimal` controls desktop app fill-ins. `auto` uses `minimal` when an existing GNOME/KDE/Plasma desktop is detected and `full` otherwise. `minimal` still installs the Niri/Noctalia/Ghostty baseline, but skips bundles listed in `MINIMAL_DESKTOP_SKIP_BUNDLE_IDS`.
- A base bundle failure is fatal because the result would not be a functioning desktop baseline.
- `DEFAULT_BUNDLE_IDS` is intentionally empty while the base desktop is being hardened. AI, development, .NET, office, gaming, media, and extra browser bundles are opt-in.
- Wizard and `--select` choices add optional categories. Optional package/source/action failures warn and continue where possible so one broken optional component does not prevent the base desktop setup from completing.
- Each generated plan writes `base-rationale.tsv` under the plan directory so required base package, action, Flatpak runtime, and source ownership is explicit. The report includes a responsibility class, consumer, and reason for each base item.
- Each generated plan writes `files/managed-config-policy.tsv` so planned config paths are visible as `stow`, `seed-if-missing`, `first-run`, or `generated`, with the conflict behavior shown before install.

## Shell Tooling

- The base install always includes Zsh and its managed config.
- The base install always includes Zsh, Oh My Zsh setup, Starship, zoxide, fastfetch, `gh`, btop, fd, fzf, bat, Yazi, and their managed dotfiles.
- The Starship prompt uses a managed static config with a fallback Noctalia palette; dynamic Noctalia template-driven theming is deferred until the v5 baseline stabilizes.
- Zsh setup bootstraps Oh My Zsh, installs the managed `~/.zshrc`, and changes the target user's login shell to `/bin/zsh`.
- `doctor` checks the selected shell tools and their managed config files when they are present in the saved plan.

## Install

Remote install:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-fedora/main/bootstrap.sh | bash -s -- --ref main
```

This prints the bootstrap packages it will install, asks for confirmation, clones the repo to `~/zz-fedora` by default, and then launches the installer.

Pinned install:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-fedora/main/bootstrap.sh | bash -s -- --ref v0.1.0
```

Unattended dry-run bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-fedora/main/bootstrap.sh | bash -s -- --yes --dry-run --ref main
```

Clone to a custom directory:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-fedora/main/bootstrap.sh | bash -s -- --dir "$HOME/src/zz-fedora" --ref main
```

Local install:

```bash
git clone https://github.com/bgmulinari/zz-fedora.git
cd zz-fedora
./install.sh wizard
```

Build an online Fedora installer ISO from the current checkout:

```bash
sudo dnf install lorax rsync xorriso
scripts/build-fedora-installer-iso.sh \
  --input ~/Downloads/Fedora-Everything-netinst-x86_64-<release>.iso \
  --output release/zz-fedora.iso
```

The generated ISO keeps Anaconda in charge of disk and user setup, hides the
built-in Software Selection spoke, and always installs the managed desktop
baseline. Its `ZZ Fedora` add-on lets you select the same optional package
catalogs exposed by the normal setup wizard, then runs the unattended Fedora
install path as an Anaconda progress-reporting task for the created regular
user. See
`docs/fedora-installer-iso.md`.

Non-interactive install:

```bash
./install.sh install --yes
./install.sh install --yes --desktop-app-profile minimal
./install.sh install --yes --select browser=brave --select dev=vscode,neovim
```

Supported commands:

```bash
zz doctor
zz logs --tail
zz debug
zz first-run
zz defaults
zz dotnet devcert status
zz dotnet devcert create
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
- Noctalia Greeter/greetd enablement
- managed dotfiles through `stow --restow`
- managed dotfile conflict previews before Stow moves or backs up existing files
- modular Niri config under `~/.config/niri/cfg/`, with display config seeded only when absent
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
- starting greetd immediately
- full desktop environment installation
- immutable Fedora Atomic support
- non-Fedora operating systems

## Third-Party Source Warnings

- Fedora COPRs are optional or required depending on the base and selected component set. Review them before enabling.
- RPM Fusion is part of the protected Fedora base source set so appstream metadata and RPM Fusion packages are available before optional package planning.
- Flathub is part of the protected Fedora base source set because the base plan installs GTK Flatpak theme runtimes and optional Flatpak apps use the same remote.
- `lionheartp/Hyprland` is a required Copr source for Noctalia v5 and Noctalia Greeter.
- Terra is a required base source for Ghostty. Its generated source-trust line is marked as an explicit bootstrap exception.
- Selecting `zsh` also fetches Oh My Zsh plus the `zsh-autosuggestions` and `zsh-syntax-highlighting` plugin repositories from GitHub.

## How To Extend

Add a package:

1. Put the package name in the appropriate Fedora/source manifest under `packages/`.
2. Reference that manifest from a bundle descriptor.
3. Add the bundle to `BASE_BUNDLE_IDS` only if it is required for the non-optional functioning desktop baseline. Otherwise expose it through `DEFAULT_BUNDLE_IDS` or a choice file.

Add a source:

1. Add a `.source` descriptor under `sources/`.
2. Teach `lib/fedora.sh` how to enable it if it is a new source kind.
3. Reference the source ID from a bundle descriptor.
4. Mark sources required only when a base bundle depends on them.

Add a wizard choice:

1. Add or update the relevant `choices/*.conf` TSV.
2. Ensure referenced sources and manifests exist.
3. The planner will include it in `list-choices`, validation, and plan generation.

## Tests

Logs default to `$XDG_STATE_HOME/zz-fedora/logs` or `~/.local/state/zz-fedora/logs`. Set `LOG_DIR` to override the location.

The test suite uses Bats. On Fedora, install the runner with:

```bash
sudo dnf install bats
```

Run:

```bash
./tests/smoke.sh
```

That is the required fast PR gate. It covers shell syntax, manifest parsing, catalog validation, Fedora platform validation, fast planner behavior, and CLI smoke checks. It does not run `shellcheck` unless `ZZ_TEST_LINT=1` is set.

Run the full regression suite with:

```bash
./tests/full.sh
./tests/full.sh --timings
./tests/profile.sh
```

`tests/full.sh` runs all Bats suites and `shellcheck` when available. When GNU Parallel or `rush` is installed, smoke and full run independent test files concurrently while preserving serial order within each file; set `ZZ_TEST_JOBS=1` to force a sequential run or another positive integer to control concurrency. `tests/profile.sh` stays sequential, prints suite timings, and fails when a Bats file exceeds `ZZ_TEST_PROFILE_THRESHOLD`, defaulting to 15 seconds.
