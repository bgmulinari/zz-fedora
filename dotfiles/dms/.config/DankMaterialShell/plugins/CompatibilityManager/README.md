# Proton Manager

A DMS plugin and desktop application for installing Proton, Wine and
graphics runtimes across launchers, with per-game Steam live switching.
Python 3 is the only required helper dependency; DMS supplies the interface.
The desktop entry appears under **Apps** and opens a movable, resizable window
using the same component as System Monitor. The window is created on demand and
unloaded when closed and idle; reopening starts a fresh UI session. Closing cancels
read-only requests. Explicit installs, selections and removals finish before the
session unloads. No polling or window models remain active while closed and idle;
the small plugin entry remains available for launcher IPC. Release metadata caches
on disk are independent of the window lifecycle.

## Installation

Requires DankMaterialShell, Quickshell and Python with safe tar extraction support
(Python 3.12 or newer; `.tar.zst` releases require Python 3.14 or newer).
The optional authenticated `gh` CLI increases the GitHub API allowance.

Place this plugin directory under `~/.config/DankMaterialShell/plugins/`, enable
**Proton Manager** in DMS plugin settings, and install the bundled
`proton-manager.desktop` into `~/.local/share/applications/` to add its application
entry. The desktop file invokes `dms ipc call plugins toggle protonManager`.

Choose **Install for** to select a detected launcher, then **Source** under
**Download**. Native and Flatpak installations stay separate. The manager discovers:

- Steam: custom Proton builds, installed games and the live selector.
- Heroic: separate Proton and Wine destinations, plus DXVK and VKD3D-Proton.
- Lutris: Proton and Wine runners, plus DXVK and VKD3D-Proton.
- Bottles: Proton and Wine runners.
- WineZGUI: Wine runners.

Open a launcher once to create its settings, then refresh. Outside Steam, choose
installed builds in the launcher's game settings. The manager does not rewrite
those settings. **Files** opens the installed build directory.

Sources include GE-Proton, Proton-CachyOS, Proton-EM, Proton-Wineland, Proton-RTSP,
DWProton, published Proton-TKG releases, legacy Wine-GE and Lutris-Wine, Kron4ek's
Wine/Staging/TKG variants, DXVK and VKD3D-Proton. Sources are filtered by destination.
CPU architecture and x86-64 feature levels filter assets; variants remain separate
rows. Preview releases are labelled. Scrolling near the bottom loads the next page
without resetting the scroll position. Search filters loaded builds; **Search older
releases** explicitly fetches the next page, avoiding a burst of API requests for a
query with no matches. Automatic loading also pauses when a page adds no compatible
builds; **Search older releases** continues one page at a time. A failed page shows **Retry** and keeps loaded builds;
refreshing or changing the destination/source starts a fresh catalog.
Published Proton-TKG releases are older than its CI builds; CI artifacts and tools
such as SteamTinkerLaunch, Boxtron and Luxtorpeda are not included.

The layout follows System Monitor: tabs and search share a toolbar, the table
fills the available space, and release notes open beside the build list.
Ctrl+1/2/3 switches tabs and Ctrl+F searches. Release notes use GitHub's rendered
HTML through Qt rich text, including short commit and issue links. Raw Markdown
is used when rendered HTML is unavailable, including non-GitHub sources.

## Steam live switching

1. Open Steam once, then search **Proton Manager** in the DMS launcher and open it.
2. Click **Set as active** beside an installed build, or install one from
   **Download** first. Downloads use the selected asset matching this computer's CPU.
3. Restart Steam once to discover **Proton Manager**. In each game's Steam
   **Properties → Compatibility**, force **Proton Manager** as its compatibility tool.
4. Choose a game in the plugin and pick its build. Subsequent changes apply on
   the next game launch without restarting Steam. **Use active build** clears an
   override; numeric App IDs also work for games absent from the installed list.

The plugin does not enable Proton for native games or rewrite Steam's settings.
A displayed override applies only when that game uses **Proton Manager** in Steam.
**Set as active** selects the build used by games without an override.
The active build is pinned first with a green background and bold name. Remaining
builds sort newest first by their embedded build timestamp, falling back to the
directory modification time when unavailable.
Choosing a game opens an explicit game-specific selection view; **Back to
games** leaves that view, and the Installed tab always returns to default selection. A running game's runtime stays unchanged by selections.

## Runtime and storage

The first default creates `compatibilitytools.d/Proton-Manager/` inside the
chosen Steam installation. Its manifest remains fixed to that build's Steam
Linux Runtime. Only builds declaring the same `require_tool_appid` can be routed;
others remain visible and must be selected directly in Steam. The launcher also
checks the runtime at launch, in case Steam has updated an official build.
Steam must have downloaded that runtime before the first launch.

Selections are atomic JSON snapshots inside that directory. The wrapper executes
installed builds in place, with original arguments and Steam's remaining runtime
paths preserved. It does not duplicate multi-gigabyte Proton trees. Externally
installed builds must remain installed and accessible inside Steam's sandbox.
A missing or incompatible selected build stops the launch with an error directing
you to choose another installed build. Games without an override use the active build.

Release sources are declared in `scripts/providers.py`; launcher paths and supported
runtime types live in `scripts/targets.py`. Downloads are checked against upstream
SHA-512/SHA-256 checksum files or release asset digests when available. Older assets
without a checksum are explicitly labelled **HTTPS only**; their size is checked,
but they are not reported as checksum-verified. Each install records provenance.

Archives are staged in the destination filesystem and safely extracted before an
atomic rename. Gzip, XZ, bzip2 and Zstandard tar archives are supported by compatible Python versions (Zstandard requires Python 3.14). Cancellation or failure removes staging.
Downloads are limited to 2 GiB and extracted contents to 8 GiB; staging requires
8 GiB plus archive size free. A source failure produces a visible error without
preventing local inventory or Steam selection from working offline.

When `gh` is installed and authenticated for github.com, release metadata is fetched
with `gh api`. Credentials remain in the CLI's own credential store. When the CLI
is absent, signed out or its authentication expires, public HTTPS requests are used.
This is optional: `gh` is not a required package or startup dependency. Asset downloads
continue over HTTPS. A rate limit on authenticated requests does not trigger anonymous
fallback; both request budgets have separate persisted cooldowns.

Public release pages are cached for one hour under
`$XDG_CACHE_HOME/proton-manager/releases` (normally `~/.cache/proton-manager/releases`),
with at most 64 response files retained. Expired pages use ETag/Last-Modified validation;
offline or rate-limited requests can use stale pages with a visible notice. Install
reuses metadata from cached release pages. GitHub's reset and Retry-After headers
are honored across helper processes; uncached pages must wait for the cooldown.
The optional CLI authentication check is cached for five minutes and is only needed
when a page needs a network request. Refresh keeps visible results until it succeeds.

Only builds installed by this plugin can be removed. Removal requires Steam and
games to be closed, and refuses builds referenced by any discovered Proton Manager selector
and its per-game selections. Removal never touches Steam-managed or external builds.
Unreadable selector configurations appear as scan warnings. They block removal of
builds visible to that Steam library, while unrelated launcher builds remain manageable.
For other launchers, removal also checks that the launcher is closed and that its
JSON/YAML settings do not reference the build. Settings and game prefixes are never
modified. Unselected builds can be removed once the relevant launcher and games are closed.

This manages runtime installations, not Wine prefixes.
No accounts, background downloads, telemetry, or automatic runtime upgrades.

## Development

The `scripts/manager.py` helper accepts `scan`, `releases`, `select`,
`install`, and `remove`; it emits newline-delimited JSON results and progress.
Mutations hold a per-installation nonblocking lock. `scripts/router.py` is copied
into the stable Steam entrypoint on registration, so launching games does not
need the shell running. Tests use disposable homes and fake Proton launchers:
`bats tests/compatibility_manager.bats`.

The stable-entry technique was informed by `proton-selector`; discovery and release handling were informed by `ProtonUp-Qt`.
The implementation here is independent and uses the Python standard library.
