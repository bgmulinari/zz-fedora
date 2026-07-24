# ZZ Fedora

A Fedora x86_64 post-install bootstrapper for a [Niri](https://github.com/niri-wm/niri) and [Noctalia](https://github.com/noctalia-dev/noctalia) desktop.

## Install

The easiest way to get started is the bootstrap script:

```bash
curl -fsSL https://zz.036477.xyz | bash
```

To install from a local checkout instead:

```bash
git clone --filter=blob:none --depth=1 https://github.com/bgmulinari/zz-fedora.git ~/.zz
cd ~/.zz
./install.sh wizard
```

## Documentation

- [ZZ command-line utility](docs/zz-cli.md)
- [Fedora installer ISO](docs/fedora-installer-iso.md)
- [Configuration ownership and layering](docs/dotfiles-layering.md)
