# Fedora Installer ISO

This project can build an online Fedora installer ISO that embeds the current
checkout and exposes an Anaconda add-on named `ZZ Fedora`. This custom ISO
always installs the managed desktop baseline; the add-on shows the same
optional package catalogs as the normal setup wizard. An Anaconda D-Bus task
from the add-on runs the normal `./install.sh install --yes --use-saved` path
during the installer configuration phase and reports step progress to the
graphical progress screen. The ISO is not an
offline package mirror: Fedora, RPM Fusion, COPR, Terra, Flathub, GitHub-hosted
shell/font assets, and any selected upstream installers are still fetched from
the network exactly as they are during the bootstrap flow.

The supported build and installation target is Fedora 44 x86_64.

The implementation follows Fedora/Lorax's Kickstart ISO approach:

- `mkksiso` adds a Kickstart and extra files to an existing installer ISO and
  updates the boot configuration to run that Kickstart.
- A generated `images/product.img` contains the Anaconda add-on payload under
  `/usr/share/anaconda/addons/`, matching Red Hat's documented installer
  customization layout. The product image also includes a snapshot of
  `choices/` so the spoke can render optional package catalogs inside Anaconda.
  It also installs an Anaconda configuration snippet that hides the built-in
  `SoftwareSelectionSpoke`; all optional setup choices are made in the
  `ZZ Fedora` spoke under Anaconda's existing Software section.
- The product image installs D-Bus policy and service activation files for
  `org.fedoraproject.Anaconda.Addons.ZZFedora`. Anaconda starts that module
  with its other add-ons, collects its `install_with_tasks()` task, and displays
  the task's `report_progress()` messages in the normal installer progress UI.
- The Kickstart leaves disk partitioning, locale, timezone, hostname, root
  password, user creation, and ZZ Fedora execution to Anaconda.
- The embedded checkout is copied to `~/zz-fedora` for the
  first regular user created in Anaconda by the add-on task.
- The checkout is a tracked runtime snapshot, not a copy of the developer
  repository's `.git` directory. A payload marker allows installer preflight
  to recognize the snapshot. A later bootstrap run backs it up and replaces it
  with a normal Git clone before updating.
- The add-on writes the chosen optional packages to the normal saved selection
  format. The installer is invoked with `--use-saved`,
  `--desktop-app-profile full`, and user-scoped state paths so
  the result matches the unattended bootstrap baseline plus the Anaconda
  choices.
- The Kickstart enables Anaconda's built-in `updates` repository by name. This
  makes Anaconda resolve its original package transaction against both the
  Fedora release and current updates repositories, matching the online
  Everything installer without a second full-system upgrade transaction.
  The repository is intentionally not redefined with `--metalink`: Anaconda
  disables built-in repositories while loading an explicit URL source, and a
  URL redefinition of the existing `updates` repository does not re-enable it.

## Build

On Fedora, install the builder tools:

```bash
sudo dnf install lorax rsync xorriso
```

Build from a Fedora netinst or DVD ISO:

```bash
scripts/build-fedora-installer-iso.sh \
  --input ~/Downloads/Fedora-Everything-netinst-x86_64-<release>.iso \
  --input-sha256 <sha256-from-the-signed-fedora-checksum-file> \
  --output release/zz-fedora.iso
```

For a fully bootable UEFI USB image, run the builder with privileges when your
Fedora/Lorax version requires it:

```bash
sudo scripts/build-fedora-installer-iso.sh \
  --input ~/Downloads/Fedora-Everything-netinst-x86_64-<release>.iso \
  --output release/zz-fedora.iso
```

`--skip-mkefiboot` is available for development-only builds where you do not
need `mkksiso` to update the embedded EFI boot image.

The builder supports Fedora 44 x86_64 input media. Always pass
`--input-sha256` using the digest from Fedora's signed checksum file. The
embedded repository payload is assembled only from Git-tracked runtime files;
`.git`, tests, local logs, caches, ignored files, and unrelated untracked files
are never copied into the ISO.

## Install Flow

1. Write the generated ISO to USB.
2. Boot the Fedora install entry.
3. Complete the Anaconda screens, including creating a regular user.
4. Open the `ZZ Fedora` Anaconda spoke and select any optional browsers,
   AI tools, development tools, .NET components, office apps, gaming apps, or
   multimedia packages you want.
5. Start installation.
6. The add-on task copies this checkout to the installed system and runs:

```bash
./install.sh install --yes --use-saved --desktop-app-profile full --no-tui --target-user "$target_user"
```

System services are enabled for first boot during ISO installs instead of being
started inside the Anaconda chroot. Anaconda installs Fedora packages from the
release and updates repositories in one transaction before the add-on enables
RPM Fusion, COPR, Terra, vendor repositories, or Flathub.
First-login/session-sensitive work remains registered through the existing
`zz first-run` path.

## VM Validation

Run the unattended VM harness against the same Fedora input ISO before publishing
changes to the installer path:

```bash
scripts/test-fedora-installer-vm.sh \
  --input ~/Downloads/Fedora-Everything-netinst-x86_64-<release>.iso
```

The harness builds a VM-only Kickstart ISO, boots the generated ISO's Fedora
bootloader by default, starts Anaconda in graphical mode over a local QEMU VNC
display, and runs the same embedded checkout and installer invocation used by
the production add-on task. Use `--installer-ui text` for serial-console
debugging, `--boot-mode direct` for faster kernel/initrd boot debugging, and
`--boot-mode uefi` when you specifically need to exercise the generated ISO
UEFI firmware path.

For fast, deterministic iteration without VNC, use
`--boot-mode direct --installer-ui text --graphics none`. Text-mode runs fail
unless the serial log contains both the Doctor 9/9 marker and the final ZZ
Fedora completion marker.

Niri needs a 3D-capable virtual GPU for post-install desktop validation. Use
`--graphics egl-headless` when the VM needs to boot or test the installed Niri
session; this selects QEMU's headless OpenGL display with `virtio-vga-gl`.

The add-on task wraps the bootstrap with a total timeout and the normal
per-command timeout so Anaconda fails with logs instead of waiting forever on a
stuck network or package command. During the ZZ Fedora phase, the GTK
progress label changes as installer steps and substeps start. While a long DNF
or Flatpak transaction is running, the task also reflects selected package
manager output, such as dependency resolution, downloads, transaction tests, and
numbered package operations. When debugging, inspect
`/root/zz-fedora-kickstart.log`, the target user's
`~/.local/state/zz-fedora/logs/latest.log`, and
`~/.local/state/zz-fedora/logs/install-progress.tsv`.

## References

- Lorax `mkksiso`: https://weldr.io/lorax/mkksiso.html
- Lorax `livemedia-creator`: https://weldr.io/lorax/livemedia-creator.html
- Fedora live media compose notes: https://fedoraproject.org/wiki/Livemedia-creator-_How_to_create_and_use_a_Live_CD
- Red Hat Customizing Anaconda, developing installer add-ons: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/customizing_anaconda/developing-installer-add-ons_customizing-anaconda
- Red Hat Customizing Anaconda, creating `product.img`: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/customizing_anaconda/completing-post-customization-tasks_customizing-anaconda
- Red Hat Customizing Anaconda, installer configuration files: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/customizing_anaconda/branding-and-chroming-the-graphical-user-interface_customizing-anaconda#customizing-the-default-configuration_branding-and-chroming-the-graphical-user-interface
- Fedora Remix secondary trademark guidance: https://fedoraproject.org/wiki/Legal%3ASecondary_trademark_usage_guidelines
