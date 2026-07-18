# ZZ Fedora

A Fedora x86_64 post-install bootstrapper for a [Niri](https://github.com/niri-wm/niri) and [Noctalia](https://github.com/noctalia-dev/noctalia) desktop.

## Install

The easiest way to get started is the bootstrap script:

```bash
curl -fsSL https://zz.036477.xyz | bash
```

To install from a local checkout instead:

```bash
git clone --filter=blob:none https://github.com/bgmulinari/zz-fedora.git
cd zz-fedora
./install.sh wizard
```

## Repository layout

```
install.sh    Installer entry point and orchestrator
bootstrap.sh  Installs prerequisites, clones the repo, hands off to install.sh
modules/      Ordered install steps (preflight, sources, plan, packages, ...)
lib/          Shared Bash logic used by the installer and modules
choices/      Wizard choice catalogs; each choice maps to bundle IDs
bundles/      Bundle composition; bundles reference package lists and sources
packages/     Package lists (.pkgs, .flatpaks) and direct actions (.actions)
sources/      Repository definitions with trust metadata (.source)
dotfiles/     Portable user configuration deployed as Stow packages
templates/    Files rendered by the installer rather than deployed via Stow
bin/          The installed zz post-install launcher and its subcommands
iso/          Fedora installer ISO integration (Kickstart, Anaconda add-on)
tests/        Bats regression suites
```

The data layer chains choices → bundles → packages and sources: the wizard
resolves selected choices to bundles, and each bundle declares the package
lists, actions, and repositories it needs.

## After install

The installer deploys the `zz` launcher for post-install maintenance, for
example `zz doctor` to check desktop readiness and `zz update` to update
packages and developer tools. See [ZZ command-line utility](docs/zz-cli.md).

## Building the installer ISO

The repository can also build a self-installing Fedora ISO that runs the same
installer path; see [Fedora installer ISO](docs/fedora-installer-iso.md).

## Documentation

- [ZZ command-line utility](docs/zz-cli.md)
- [Fedora installer ISO](docs/fedora-installer-iso.md)
- [Dotfiles and templates layering](docs/dotfiles-layering.md)
