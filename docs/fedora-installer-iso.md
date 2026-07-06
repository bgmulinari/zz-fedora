# Fedora Installer ISO

This project can build an online Fedora installer ISO that embeds the current
checkout and runs the normal `./install.sh install --yes` path during Anaconda
`%post`. The ISO is not an offline package mirror: Fedora, RPM Fusion, COPR,
Terra, Flathub, GitHub-hosted shell/font assets, and any selected upstream
installers are still fetched from the network exactly as they are during the
bootstrap flow.

The implementation follows Fedora/Lorax's Kickstart ISO approach:

- `mkksiso` adds a Kickstart and extra files to an existing installer ISO and
  updates the boot configuration to run that Kickstart.
- The Kickstart leaves disk partitioning, locale, timezone, hostname, root
  password, and user creation to Anaconda.
- The embedded checkout is copied to `~/zz-linux-setup` for the first regular
  user created in Anaconda.
- The installer is invoked with `--distro fedora --desktop-app-profile full`
  and user-scoped state paths so the result matches the unattended bootstrap
  baseline.

## Build

On Fedora, install the builder tools:

```bash
sudo dnf install lorax rsync
```

Build from a Fedora netinst or DVD ISO:

```bash
scripts/build-fedora-installer-iso.sh \
  --input ~/Downloads/Fedora-Everything-netinst-x86_64-<release>.iso \
  --output release/zz-linux-setup-fedora.iso
```

For a fully bootable UEFI USB image, run the builder with privileges when your
Fedora/Lorax version requires it:

```bash
sudo scripts/build-fedora-installer-iso.sh \
  --input ~/Downloads/Fedora-Everything-netinst-x86_64-<release>.iso \
  --output release/zz-linux-setup-fedora.iso
```

`--skip-mkefiboot` is available for development-only builds where you do not
need `mkksiso` to update the embedded EFI boot image.

## Install Flow

1. Write the generated ISO to USB.
2. Boot the Fedora install entry.
3. Complete the Anaconda screens, including creating a regular user.
4. Start installation.
5. The Kickstart copies this checkout to the installed system and runs:

```bash
./install.sh install --yes --distro fedora --desktop-app-profile full --no-tui --target-user "$target_user"
```

System services are enabled for first boot during ISO installs instead of being
started inside the Anaconda chroot. First-login/session-sensitive work remains
registered through the existing `zz first-run` path.

## References

- Lorax `mkksiso`: https://weldr.io/lorax/mkksiso.html
- Lorax `livemedia-creator`: https://weldr.io/lorax/livemedia-creator.html
- Fedora live media compose notes: https://fedoraproject.org/wiki/Livemedia-creator-_How_to_create_and_use_a_Live_CD
- Fedora Remix secondary trademark guidance: https://fedoraproject.org/wiki/Legal%3ASecondary_trademark_usage_guidelines
