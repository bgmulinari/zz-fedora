# Fedora Installer ISO Architecture

This design note records how the installer ISO is put together and why. For
the user-facing build, install-flow, and VM-validation procedure, see
[docs/fedora-installer-iso.md](../fedora-installer-iso.md).

The implementation follows Fedora/Lorax's Kickstart ISO approach:

- When no input path is supplied, the build-time tooling refreshes Fedora's
  official `releases.json`, selects the highest stable numeric Everything
  release for x86_64, and caches that netinst image under the ignored
  `release/input/` directory. The matching checksum document is cached
  alongside it, while Fedora's aggregate OpenPGP keyring is refreshed on each
  build. The builder authenticates the checksum document with `gpgv`, derives
  the expected signer from the locally installed certificate for the resolved
  release, and compares the input SHA-256 with both signed and release-metadata
  values; an invalid cached input or checksum document is replaced and
  rechecked. When no output
  path is supplied, the builder derives
  `release/zz-fedora-<architecture>-<release>.iso` from the validated input ISO
  metadata.
- `mkksiso` adds a Kickstart and extra files to an existing installer ISO and
  updates the boot configuration to run that Kickstart.
- A generated `images/product.img` contains the Anaconda add-on payload under
  `/usr/share/anaconda/addons/`, matching Red Hat's documented installer
  customization layout. The product image also includes a fallback snapshot of
  `choices/` for add-on development and diagnostics. During an ISO install, the
  spoke renders the catalogs from the refreshed remote runtime instead.
  It also installs an Anaconda configuration snippet that hides the built-in
  `SoftwareSelectionSpoke`; all optional setup choices are made in the
  `ZZ Fedora` spoke under Anaconda's existing Software section.
- The product image installs D-Bus policy and service activation files for
  `org.fedoraproject.Anaconda.Addons.ZZFedora`. Anaconda starts that module
  with its other add-ons, collects its `install_with_tasks()` task, and displays
  the task's `report_progress()` messages in the normal installer progress UI.
- Product-image content is split by kind: `iso/anaconda-addon/` holds the
  Python add-on payload, and `iso/anaconda-addon-data/` holds every non-Python
  file staged into the product image — the D-Bus policy and activation files,
  the `conf.d` snippet, and the `.buildstamp` template. The build scripts only
  stage these tracked files and substitute release-derived values such as
  `@FEDORA_RELEASE@`; they do not embed product-image content inline. The
  staged add-on additionally carries a generated `build-info.conf` stamp
  recording the Git revision (and dirty state) of the checkout that produced
  the image, so an installed ISO can be correlated with repository state.
- The Kickstart leaves disk partitioning, locale, timezone, hostname, root
  password, user creation, and ZZ Fedora execution to Anaconda.
- The embedded checkout is a tracked runtime snapshot, not a copy of the
  developer repository's `.git` directory. It provides the stable loader that
  refreshes `main` before the ZZ Fedora choices become available.
- The graphical and text add-on spokes wait for Anaconda's installation-source
  setup to reach a terminal state before downloading the current remote
  archive. This lets users configure Wi-Fi, static networking, or a source
  proxy through Anaconda first. A failed refresh leaves the mandatory spoke
  incomplete and re-entering it retries the download.
- The loader (`iso/lib/runtime-loader.sh`, executed inside Anaconda by the
  add-on) filters the archive to the runtime paths declared by that revision's
  `iso/payload-paths.conf`, and stages it at
  `/run/zz-fedora/repository`. Failure to fetch or validate that snapshot stops
  the installation instead of silently using stale catalogs. If TLS validation
  reports an invalid installer clock, the loader uses chronyd to synchronize
  time and retries the download once. The embedded manifest is used only when
  refreshing from an older revision that predates the manifest.
- Both the graphical and text spokes read `choices/` from that refreshed
  snapshot. New rows and new `choices/*.conf` catalogs are discovered without
  rebuilding the ISO. The add-on later copies the exact same snapshot to
  `~/zz-fedora` for the first regular user created in Anaconda and runs the
  installer from it. The generated payload marker records the resolved archive
  revision and remote ref. A later bootstrap run backs up the snapshot and
  replaces it with a normal Git clone before updating.
- The add-on writes the chosen desktop app profile and optional packages to
  the normal saved selection format. The installer is invoked with
  `--use-saved`, the selected `--desktop-app-profile full|minimal`, and
  user-scoped state paths so the result matches the selected baseline plus the
  Anaconda choices.
- The Kickstart enables Anaconda's built-in `updates` repository by name. This
  makes Anaconda resolve its original package transaction against both the
  Fedora release and current updates repositories, matching the online
  Everything installer without a second full-system upgrade transaction.
  The repository is intentionally not redefined with `--metalink`: Anaconda
  disables built-in repositories while loading an explicit URL source, and a
  URL redefinition of the existing `updates` repository does not re-enable it.

## References

- Lorax `mkksiso`: https://weldr.io/lorax/mkksiso.html
- Lorax `livemedia-creator`: https://weldr.io/lorax/livemedia-creator.html
- Fedora live media compose notes: https://fedoraproject.org/wiki/Livemedia-creator-_How_to_create_and_use_a_Live_CD
- Red Hat Customizing Anaconda, developing installer add-ons: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/customizing_anaconda/developing-installer-add-ons_customizing-anaconda
- Red Hat Customizing Anaconda, creating `product.img`: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/customizing_anaconda/completing-post-customization-tasks_customizing-anaconda
- Red Hat Customizing Anaconda, installer configuration files: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/customizing_anaconda/branding-and-chroming-the-graphical-user-interface_customizing-anaconda#customizing-the-default-configuration_branding-and-chroming-the-graphical-user-interface
- Fedora Remix secondary trademark guidance: https://fedoraproject.org/wiki/Legal%3ASecondary_trademark_usage_guidelines
