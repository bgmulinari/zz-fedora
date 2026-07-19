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

The default profile is `full`: every optional non-browser choice is
preselected, while Firefox is the only preselected browser and therefore the
default browser. Both Anaconda UIs also expose the `minimal` desktop app
profile. It keeps the Niri and Noctalia baseline, suppresses the Desktop
catalog defaults and full-profile desktop integration bundles, and still
allows individual desktop apps to be selected explicitly. Other optional
catalogs keep their normal defaults in both profiles.

The supported build and installation target is Fedora x86_64 at or above the
repository's configured minimum release.

For the design rationale — the Lorax/`mkksiso` approach, `product.img`
contents, the Anaconda D-Bus add-on wiring, and the remote runtime refresh —
see
[docs/design/fedora-installer-iso-architecture.md](design/fedora-installer-iso-architecture.md).

## Build

On Fedora, install the builder tools:

```bash
sudo dnf install curl gnupg2 jq lorax rsync xorriso
```

Build with the latest stable Fedora Everything x86_64 netinst ISO:

```bash
sudo iso/scripts/build-fedora-installer-iso.sh
```

Publishable builds require root privileges because `mkksiso` refreshes the
embedded EFI boot image through loop mounts; development builds that pass
`--skip-mkefiboot` skip that refresh and run unprivileged. The builder checks
for the privileges before it resolves or downloads the input ISO, so a build
cannot do the large download and then fail for lack of access. A `sudo` build
restores ownership of the `release/` outputs and download cache to the
invoking user on exit.

When `--input` is omitted, the builder refreshes Fedora's machine-readable
`releases.json`, selects the highest stable numeric Everything release for
x86_64, and downloads that ISO to `release/input/`. Later builds reuse the ISO
as long as it remains the latest release. Downloads are written to `.part`
files and moved into place only after they complete.

The builder also caches Fedora's clear-signed checksum file and refreshes its
OpenPGP keyring in `release/input/`. On every build, it verifies the checksum
document with `gpgv`, derives the expected signer fingerprint from the
installed Fedora release certificate under `/etc/pki/rpm-gpg/`, and checks the
ISO's SHA-256 against both the authenticated checksum and release metadata.
This verification also runs for a cached ISO. If the cached ISO or the cached
checksum document fails verification, the builder removes it, downloads a
replacement, and verifies the replacement before continuing; a downloaded
checksum that still fails verification is removed rather than left in the
cache. Keep the host's `fedora-repos` package current so the next
stable release's certificate is present when Fedora publishes that release.
Set `ZZ_FEDORA_RELEASE_KEY_DIR` to read the release certificates from another
directory; pass it on the `sudo` command line, as in
`sudo ZZ_FEDORA_RELEASE_KEY_DIR=<dir> iso/scripts/build-fedora-installer-iso.sh`,
because `sudo` strips exported environment variables by default.

When `--output` is omitted, the builder reads the release and architecture
from the input ISO and writes `release/zz-fedora-<architecture>-<release>.iso`.
Pass `--output` to override that path.

To build from another local Fedora installer ISO, pass it explicitly and
verify it with the digest from Fedora's signed checksum file:

```bash
sudo iso/scripts/build-fedora-installer-iso.sh \
  --input /path/to/Fedora-Everything-netinst-x86_64-<release>-<compose>.iso \
  --input-sha256 <sha256-from-the-signed-fedora-checksum-file>
```

`--skip-mkefiboot` is available for development-only builds where you do not
need `mkksiso` to update the embedded EFI boot image; those builds do not
require root privileges. Validate publishable media without that flag.

The builder supports x86_64 input media at or above `MINIMUM_FEDORA_RELEASE`
from `config/defaults.sh`. When supplying `--input`, pass `--input-sha256`
using the digest from Fedora's signed checksum file. The automatic input is
always checked against Fedora's signed checksum; supplying `--input-sha256`
with it adds a consistency check against that authenticated digest. Input and
output paths must differ, and generated images belong under the ignored
`release/` directory rather than in Git. The
embedded repository payload is assembled only from Git-tracked runtime files;
`.git`, tests, local logs, caches, ignored files, and unrelated untracked files
are never copied into the ISO.

### CI release build

The manually triggered `Release ISO` GitHub Actions workflow
(`.github/workflows/release-iso.yml`) first runs the CI test gate — the
Fedora container matrix, which deduplicates to a single leg while
`fedora:latest` is the same image as the minimum supported release — and
then builds the ISO with the verified automatic Fedora input and replaces the
repository's single rolling GitHub release (tag `latest`) with the fresh ISO
and its SHA-256 checksum file. Start it from the repository's Actions tab.
The workflow does not run the VM validation below; run that locally before
triggering a release build for installer-path changes.

The ISO must still be rebuilt for changes to the Kickstart, Anaconda add-on,
base installer packages, boot integration, or remote-runtime loader. Changes
to installer modules, manifests, package choices, bundles, sources, dotfiles,
and templates are picked up from `main` when installation starts. This makes
the result intentionally time-dependent: two installations from the same ISO
can resolve different repository revisions.

## Install Flow

1. Write the generated ISO to USB.
2. Boot the Fedora install entry.
3. Complete the Anaconda screens, including creating a regular user.
4. Configure networking or the installation-source proxy if necessary. The
   `ZZ Fedora` spoke waits for source setup, then fetches and validates the
   current `main` runtime. Open it, select the full or minimal desktop app
   profile, and review its choices; the catalogs come from that fetched
   revision. Full remains the default. Selecting minimal clears the Desktop
   catalog defaults, after which individual desktop apps can be selected.
   Deselect any AI tools, development tools, .NET
   components, office apps, gaming apps, or multimedia packages you do not
   want, or change the Firefox browser selection.
5. Start installation.
6. The add-on task creates a depth-1 clone in `~/.zz`, verifies the checkout
   against the exact revision recorded by that refreshed runtime, and runs:

```bash
./install.sh install --yes --use-saved --desktop-app-profile "$desktop_app_profile" --no-tui --target-user "$target_user"
```

System services are enabled for first boot during ISO installs instead of being
started inside the Anaconda chroot. Anaconda installs Fedora packages from the
release and updates repositories in one transaction before the add-on enables
RPM Fusion, COPR, Terra, vendor repositories, or Flathub.
First-login/session-sensitive work remains registered through the existing
`zz first-run` path. Extra-data flatpaks (for example Spotify and Zoom) cannot
run their sandboxed apply step inside the chroot, so the installer records them
on a deferred list in the target user's state directory and `zz first-run`
installs them in the first login session, retrying on later logins (with a
bounded attempt budget) if an install fails.

## VM Validation

Run the unattended VM harness against the same Fedora input ISO before publishing
changes to the installer path:

```bash
iso/scripts/test-fedora-installer-vm.sh \
  --input ~/Downloads/Fedora-Everything-netinst-x86_64-<release>.iso \
  --input-sha256 <sha256-from-the-signed-fedora-checksum-file>
```

Use its direct/text/headless modes below for iteration, but validate the
generated ISO boot path for release work.

The VM harness defaults to the full profile. Pass
`--desktop-app-profile minimal` to persist a minimal selection through the
same add-on state and service path. The resulting qcow2 remains in the selected
work directory for a separate graphical boot and Niri/Noctalia login check.

The harness builds a VM-only Kickstart ISO, boots the generated ISO's Fedora
bootloader by default, starts Anaconda in graphical mode over a local QEMU VNC
display, and runs the same remote runtime refresh and installer invocation used
by the production add-on task. Use `--installer-ui text` for serial-console
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

Upstream Lorax, Anaconda, and Fedora references are listed in the
[architecture design note](design/fedora-installer-iso-architecture.md#references).
