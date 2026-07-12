# ZZ Fedora

A Fedora post-install bootstrapper for a Niri and Noctalia v5 desktop.

Supports Fedora 44 on x86_64.

## Install

The easiest way to get started is the bootstrap script:

```bash
curl -fsSL https://raw.githubusercontent.com/bgmulinari/zz-fedora/main/bootstrap.sh | bash
```

To install from a local checkout instead:

```bash
git clone --filter=blob:none https://github.com/bgmulinari/zz-fedora.git
cd zz-fedora
./install.sh wizard
```

## Documentation

- [ZZ command-line utility](docs/zz-cli.md)
- [Fedora installer ISO](docs/fedora-installer-iso.md)
