# ZZ Linux Setup

ZZ Linux Setup is a modular, idempotent Linux post-install desktop bootstrapper for a minimal Niri + Noctalia Shell desktop with KDE/Qt-oriented applications and integration. Ghostty is the default terminal. `gum` provides the primary interactive wizard.

## Status

- Fedora is the primary target for v1.
- Arch Linux support is included as experimental.
- The design keeps distro-specific logic in thin adapters so additional distros can be added later without rewriting common modules.

## Desktop Philosophy

- Niri is the compositor/session target.
- Noctalia Shell is a shell layer, not a full desktop environment.
- KDE/Qt integration is the default:
  - Dolphin instead of Nautilus
  - KWrite instead of GNOME Text Editor
  - Okular instead of Evince
  - Gwenview instead of Loupe
  - Ark instead of File Roller
  - Spectacle for screenshots
  - KDE portal backend, KDE polkit agent, Breeze theming, `qt5ct`, and `qt6ct`
- Ghostty is the default terminal.

## Session Model

- Plasma Login Manager provides the graphical login and session chooser.
- Choose the `Niri` session at login.
- Noctalia is launched from Niri autostart with `spawn-at-startup "qs" "-c" "noctalia-shell"`.
- Noctalia ships with the Niri, Qt, and KColorScheme templates pre-enabled through managed user settings.
- The installer never starts Plasma Login Manager immediately. Reboot to begin using the graphical login.

## Install

Remote install:

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/bootstrap.sh | bash -s -- --ref main
```

Pinned install:

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/bootstrap.sh | bash -s -- --ref v0.1.0
```

Local install:

```bash
git clone https://github.com/OWNER/REPO.git
cd REPO
./install.sh wizard
```

Non-interactive install:

```bash
./install.sh install --yes --select browser=firefox,brave --select dev=base
```

Supported commands:

```bash
./install.sh wizard
./install.sh install --yes
./install.sh install --dry-run
./install.sh install --use-saved
./install.sh print-plan
./install.sh doctor
./install.sh list-profiles
./install.sh list-choices
./install.sh list-sources
```

## Idempotency

The project is intended to be safe to re-run after repository updates.

Managed items:

- package sources and repositories
- package installation
- Flatpak remotes and apps
- system services
- Plasma Login Manager enablement
- managed dotfiles through `stow --restow`
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
- starting Plasma Login Manager immediately
- automatic AUR helper installation
- full Plasma desktop installation
- immutable Fedora Atomic support
- Debian, openSUSE, or NixOS support in v1

## Third-Party Source Warnings

- Fedora COPRs are optional or required depending on the selected component set. Review them before enabling.
- RPM Fusion is opt-in unless required by selected features such as codecs or Steam.
- AUR is required for Noctalia on Arch in this installer and depends on an existing `paru` or `yay`.
- Flathub is optional and is enabled explicitly or when a selected Flatpak requires it.

## How To Extend

Add a package:

1. Put the package name in the appropriate distro/source manifest under `packages/`.
2. Reference that manifest from a choice file or the mandatory base plan.

Add a source:

1. Add a `.source` descriptor under `sources/<distro>/`.
2. Teach the relevant distro adapter how to enable it if it is a new source kind.
3. Reference the source ID from a choice file or base planner rule.

Add a wizard choice:

1. Add or update the relevant `choices/<distro>/*.conf` TSV.
2. Ensure referenced sources and manifests exist.
3. The planner will include it in `list-choices`, validation, and plan generation.

Add another distro:

1. Add `distros/newdistro.sh`.
2. Add `sources/newdistro/`.
3. Add `packages/newdistro/`.
4. Add `choices/newdistro/`.

The common modules should not need changes for a straightforward new adapter.

## Tests

Run:

```bash
./tests/smoke.sh
```

That covers shell syntax, parser tests, distro detection, planner expectations, and idempotency helper behavior.
