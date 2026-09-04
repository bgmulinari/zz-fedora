"""Compare the live DMS state against the ZZ seed defaults.

DMS state is sparse: keys absent from settings.json or session.json inherit
their specification defaults. This compares three layers to report only what
a person actually changed:

  seed      templates/dms/{settings,session}-seed.json, the ZZ defaults
  upstream  the DMS spec defaults (lib/dms_spec.py)
  live      the user's ~/.config and ~/.local/state DMS files

A key is reported when the live value differs from the seed (drift in a key
the seed already pins) or, for keys the seed does not pin, when the live
value differs from the upstream default (a new candidate default).

Keys that cannot be portable defaults are never reported. See EXCLUDED.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from dms_spec import defaults, parse_spec  # noqa: E402

# Rendered from a host fact at seed time, so they must not be frozen into the
# seed files as absolute paths. lib/dms.sh overlays them. They are still
# compared, because changing the icon theme or wallpaper in the DMS UI is a
# real change worth promoting; it just lands in lib/dms.sh rather than in a
# seed file, so the report names the helper to edit instead of offering
# --apply.
DERIVED_HELPER = {
    "settings": {
        "customThemeFile": "dms_theme_file",
        "iconThemeDark": "dms_icon_theme",
        "iconThemeLight": "dms_icon_theme",
    },
    "session": {"wallpaperPath": "dms_default_wallpaper"},
}

# Values that are real for this machine or this moment but meaningless as a
# shipped default. Grouped by why they are excluded so the list stays
# reviewable.
EXCLUDED = {
    "settings": {
        # File selectors resolve to this host's filesystem. Product assets
        # belong in managed defaults and must be wired deliberately.
        "keyboardKeymapFile", "greeterWallpaperPath",
        "launcherLogoCustomPath", "dockLauncherLogoCustomPath",
        "lockScreenVideoPath", "lockScreenWallpaperPath",
        # Monitor, GPU, and device identity.
        "screenPreferences", "showOnLastDisplay", "displayProfiles",
        "connectedFrameBarStyleBackups", "selectedGpuIndex", "enabledGpuPciIds",
        "systemMonitorGpuPciId", "systemMonitorVariants",
        "desktopWidgetPositions",
        "desktopWidgetInstances", "desktopWidgetGroups",
        "desktopClockX", "desktopClockY", "systemMonitorX", "systemMonitorY",
        # Session-scoped or app-managed runtime state.
        "browserUsageHistory", "filePickerUsageHistory",
        "spotlightSectionViewModes", "appDrawerSectionViewModes",
        "launcherPluginVisibility", "launcherPluginOrder",
        "builtInPluginSettings", "configVersion",
        # Serialized as a QColor object rather than the spec's hex string, so
        # they always differ without anyone having changed a colour.
        "desktopClockCustomColor", "systemMonitorCustomColor",
        # Credentials and auth wiring.
        "lockPamPath", "lockU2fPamPath", "lockPamExternallyManaged",
        "greeterPamExternallyManaged",
    },
    "session": {
        # Where this machine is.
        "weatherLocation", "weatherCoordinates", "latitude", "longitude",
        "nightModeLocationProvider", "nightModeLocationName",
        # File selectors resolve to this host's filesystem. wallpaperPath is
        # handled separately by dms_default_wallpaper() in lib/dms.sh.
        "wallpaperPathLight", "wallpaperPathDark",
        "wallpaperCyclingFolderPath",
        # Devices attached to this machine.
        "wifiDeviceOverride", "bluetoothAdapterOverride",
        "lastBrightnessDevice", "deviceMaxVolumes",
        "brightnessExponentialDevices", "brightnessUserSetValues",
        "brightnessExponentValues", "hiddenOutputDeviceNames",
        "hiddenInputDeviceNames", "selectedGpuIndex", "enabledGpuPciIds",
        "nvidiaGpuTempEnabled", "nonNvidiaGpuTempEnabled",
        "niriOutputSettings", "hyprlandOutputSettings", "activeDisplayProfile",
        "activeDisplayProfileModes", "desktopWidgetGridSettings",
        "desktopWidgetInstancePositions", "builtInPluginState",
        # What the user did last, not what they chose.
        "lastPlayerIdentity", "launcherLastQuery", "launcherQueryHistory",
        "launcherLastMode", "launcherLastFileSearchType", "notepadLastMode",
        "appDrawerLastMode", "niriOverviewLastMode", "recentColors",
        "settingsSidebarExpandedIds", "settingsSidebarCollapsedIds",
        "vpnLastConnected", "idleInhibited", "doNotDisturb",
        "doNotDisturbUntil",
        "monitorWallpapers", "monitorWallpapersLight", "monitorWallpapersDark",
        "monitorWallpaperFillModes", "monitorCyclingSettings",
        "greeterSyncPending", "greeterSyncBaseline", "lastAppliedIconTheme",
        "configVersion",
    },
}

SPEC_FILES = {
    "settings": "SettingsSpec.js",
    "session": "SessionSpec.js",
}

SCOPES = ("settings", "session", "keybinds")

# Bind attributes worth comparing; anything else DMS reports is presentation.
BIND_FIELDS = ("action", "desc", "allowWhenLocked", "allowInhibiting",
               "cooldownMs", "repeat")


def load_json(path: pathlib.Path) -> dict:
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        raise SystemExit(f"missing file: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: {exc}")
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected a JSON object")
    return data


def flatten(value, prefix: tuple = ()) -> dict:
    """Map a nested value to {path: leaf}.

    Dicts and lists of dicts are walked so a structured setting is compared
    field by field. Comparing whole objects would report barConfigs as changed
    forever, because DMS backfills bar fields the seed deliberately omits, and
    promoting it would freeze that whole snapshot into the seed.
    """
    if isinstance(value, dict):
        out = {}
        for key, item in value.items():
            out.update(flatten(item, prefix + (key,)))
        return out
    if isinstance(value, list) and value and all(isinstance(v, dict) for v in value):
        out = {}
        for index, item in enumerate(value):
            out.update(flatten(item, prefix + (index,)))
        return out
    return {prefix: value}


MISSING = object()


def value_at_path(value, path: tuple):
    """Return a nested value or MISSING when a specification has no such path."""
    cursor = value
    for part in path:
        if isinstance(part, int):
            if not isinstance(cursor, list) or part >= len(cursor):
                return MISSING
            cursor = cursor[part]
            continue
        if not isinstance(cursor, dict) or part not in cursor:
            return MISSING
        cursor = cursor[part]
    return cursor


def index_binds(payload) -> dict:
    """Map DMS's `keybinds show` output to {key: {field: value}}."""
    out = {}
    for group in (payload or {}).get("binds", {}).values():
        for bind in group:
            out[bind["key"]] = {f: bind.get(f) for f in BIND_FIELDS}
    return out


def compare_binds(seed: dict, live: dict) -> list[dict]:
    """Diff two `keybinds show` payloads by bind key.

    Both sides are parsed by DMS itself, so the seed's comments and ordering
    -- which DMS discards the first time a bind is edited in its UI -- never
    register as differences.
    """
    seed_binds, live_binds = index_binds(seed), index_binds(live)
    rows = []
    for key in sorted(set(seed_binds) | set(live_binds)):
        before, after = seed_binds.get(key), live_binds.get(key)
        if before == after:
            continue
        kind = ("bind-added" if before is None else
                "bind-removed" if after is None else "bind-changed")
        rows.append({"key": key, "kind": kind,
                     "seed": None if before is None else before["action"],
                     "live": None if after is None else after["action"]})
    return rows


def render_path(path: tuple) -> str:
    text = ""
    for part in path:
        if isinstance(part, int):
            text += f"[{part}]"
        else:
            text += f".{part}" if text else str(part)
    return text


def path_sort_key(path: tuple) -> tuple:
    """Sort path parts structurally, keeping numeric list indexes numeric."""
    return tuple((1, part) if isinstance(part, int) else (0, part)
                 for part in path)


def set_path(target: dict, path: tuple, value) -> None:
    cursor = target
    for part, nxt in zip(path, path[1:]):
        if isinstance(part, int):
            while len(cursor) <= part:
                cursor.append({})
            if not isinstance(cursor[part], (dict, list)):
                cursor[part] = [] if isinstance(nxt, int) else {}
            cursor = cursor[part]
            continue
        if part not in cursor or not isinstance(cursor[part], (dict, list)):
            cursor[part] = [] if isinstance(nxt, int) else {}
        cursor = cursor[part]
    last = path[-1]
    if isinstance(last, int):
        while len(cursor) <= last:
            cursor.append(None)
    cursor[last] = value


def delete_path(target: dict, path: tuple) -> None:
    """Delete a nested seed override and prune containers left empty."""
    cursor = target
    parents = []
    for part in path[:-1]:
        if isinstance(part, int):
            if not isinstance(cursor, list) or part >= len(cursor):
                return
        elif not isinstance(cursor, dict) or part not in cursor:
            return
        parents.append((cursor, part))
        cursor = cursor[part]

    last = path[-1]
    if isinstance(last, int):
        if not isinstance(cursor, list) or last >= len(cursor):
            return
        cursor.pop(last)
    else:
        if not isinstance(cursor, dict) or last not in cursor:
            return
        del cursor[last]

    for parent, part in reversed(parents):
        child = parent[part]
        if not isinstance(child, (dict, list)) or child:
            break
        if isinstance(part, int):
            parent.pop(part)
        else:
            del parent[part]


def compare(scope: str, seed: dict, live: dict, upstream: dict,
            derived: dict | None = None) -> list[dict]:
    """Return the reportable differences for one scope, sorted by path."""
    skip = EXCLUDED[scope]
    helpers = DERIVED_HELPER[scope]
    derived = derived or {}
    seed_flat = flatten(seed)
    live_flat = flatten(live)
    upstream_flat = flatten(upstream)
    rows = []

    for path, live_value in live_flat.items():
        if path[0] in skip:
            continue
        if path[0] in helpers:
            # Only comparable when the caller rendered the host fact for us.
            expected = derived.get(path[0])
            if expected is not None and live_value != expected:
                rows.append({"path": path, "kind": "derived", "live": live_value,
                             "seed": expected, "helper": helpers[path[0]],
                             "reset_path": path, "reset_value": expected})
            continue
        if path in seed_flat:
            if live_value != seed_flat[path]:
                rows.append({"path": path, "kind": "changed",
                             "live": live_value, "seed": seed_flat[path],
                             "reset_path": path, "reset_value": seed_flat[path]})
            continue
        # A field the seed does not pin. Only interesting once it leaves the
        # DMS default, and only when the spec describes it at all.
        if path in upstream_flat:
            if live_value != upstream_flat[path]:
                rows.append({"path": path, "kind": "new",
                             "live": live_value, "seed": upstream_flat[path],
                             "reset_path": path,
                             "reset_value": upstream_flat[path]})
        elif path[0] in upstream:
            # The spec knows this key, but its default carries no such leaf
            # because the default is an empty object or array. Any live value
            # here is therefore a departure from the DMS default. Comparing
            # only against upstream_flat would drop these silently.
            # There is no leaf to restore, so a reset has to put the whole
            # key back to the default's empty container.
            rows.append({"path": path, "kind": "new", "live": live_value,
                         "seed": None, "seed_absent": True,
                         "reset_path": (path[0],),
                         "reset_value": upstream[path[0]]})

    # Missing live keys inherit the DMS specification default. Only call a
    # seeded path stale when the current specification no longer knows it;
    # DMS 1.6 deliberately omits default-valued keys from its state files.
    for path, seed_value in seed_flat.items():
        if path[0] in skip or path[0] in helpers or path in live_flat:
            continue
        upstream_value = value_at_path(upstream, path)
        if upstream_value is MISSING:
            if path[0] in upstream:
                # The top-level setting exists but its default container has
                # no such leaf. The effective live value is absent.
                rows.append({"path": path, "kind": "changed", "live": None,
                             "live_absent": True, "seed": seed_value,
                             "reset_path": path, "reset_value": seed_value})
            else:
                rows.append({"path": path, "kind": "stale", "live": None,
                             "seed": seed_value, "reset_path": path,
                             "reset_value": seed_value})
            continue
        if upstream_value != seed_value:
            rows.append({"path": path, "kind": "changed",
                         "live": upstream_value, "seed": seed_value,
                         "live_absent": True,
                         "reset_path": path, "reset_value": seed_value})

    # Derived values are not present in the portable seeds, but an absent live
    # key still has an effective upstream value and may therefore have drifted
    # from the host fact rendered by lib/dms.sh.
    for key, helper in helpers.items():
        path = (key,)
        if path in live_flat:
            continue
        expected = derived.get(key)
        if expected is None:
            continue
        upstream_value = value_at_path(upstream, path)
        effective = None if upstream_value is MISSING else upstream_value
        if effective != expected:
            rows.append({"path": path, "kind": "derived", "live": effective,
                         "live_absent": True, "seed": expected,
                         "helper": helper, "reset_path": path,
                         "reset_value": expected})

    for row in rows:
        row["key"] = render_path(row["path"])
    return sorted(rows, key=lambda r: r["key"])


def fmt(value) -> str:
    text = json.dumps(value, sort_keys=True)
    return text if len(text) <= 120 else text[:117] + "..."


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="dms-seed-diff",
        description="Compare live DMS settings against the ZZ seed defaults.",
    )
    ap.add_argument("--root", required=True, type=pathlib.Path)
    ap.add_argument("--home", required=True, type=pathlib.Path)
    ap.add_argument("--spec-dir", required=True, type=pathlib.Path)
    ap.add_argument("--apply", action="store_true",
                    help="write the reported differences into the seed files")
    ap.add_argument("--reset", action="store_true",
                    help="write the defaults back into the live DMS files, "
                         "backing each up first")
    ap.add_argument("--json", action="store_true", help="emit the report as JSON")
    ap.add_argument("--derived", default="{}",
                    help="JSON of the host facts lib/dms.sh overlays onto the "
                         "seeds, as {scope: {key: value}}")
    ap.add_argument("--binds", default="",
                    help="JSON as {seed: <keybinds show>, live: <keybinds "
                         "show>}; omit to skip the keybind comparison")
    ap.add_argument("--binds-seed", type=pathlib.Path,
                    help="the keybind seed file, written by --apply")
    ap.add_argument("--binds-live", type=pathlib.Path,
                    help="the live keybind fragment, written by --reset")
    ap.add_argument("keys", nargs="*",
                    help="limit to these keys (default: all reported keys)")
    args = ap.parse_args()

    if args.apply and args.reset:
        raise SystemExit(
            "--apply and --reset are opposites: --apply promotes the live "
            "state into the seed, --reset restores the seed onto the live "
            "state. Pick one."
        )

    live_paths = {
        "settings": args.home / ".config/DankMaterialShell/settings.json",
        "session": args.home / ".local/state/DankMaterialShell/session.json",
    }
    seed_paths = {
        "settings": args.root / "templates/dms/settings-seed.json",
        "session": args.root / "templates/dms/session-seed.json",
    }

    try:
        derived = json.loads(args.derived)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"--derived is not valid JSON: {exc}")

    report = {}
    for scope in SCOPES:
        report[scope] = []
    if args.binds:
        try:
            payload = json.loads(args.binds)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"--binds is not valid JSON: {exc}")
        report["keybinds"] = compare_binds(payload.get("seed"),
                                           payload.get("live"))
    for scope in ("settings", "session"):
        spec_file = args.spec_dir / SPEC_FILES[scope]
        if not spec_file.is_file():
            raise SystemExit(
                f"missing DMS spec: {spec_file}\n"
                "The comparison needs the installed shell to know each key's "
                "upstream default. Install DankMaterialShell or pass --spec-dir."
            )
        upstream = defaults(parse_spec(spec_file.read_text()))
        report[scope] = compare(scope, load_json(seed_paths[scope]),
                                load_json(live_paths[scope]), upstream,
                                derived.get(scope, {}))

    if args.keys:
        wanted = set(args.keys)
        for scope in SCOPES:
            report[scope] = [r for r in report[scope] if r["key"] in wanted]

    if args.json:
        serialisable = {
            scope: [{k: v for k, v in row.items() if k != "path"} for row in rows]
            for scope, rows in report.items()
        }
        print(json.dumps(serialisable, indent=2, sort_keys=True))
    else:
        render(report, args.apply or args.reset)

    if args.keys:
        found = {r["key"] for rows in report.values() for r in rows}
        for missing in sorted(set(args.keys) - found):
            print(f"warning: no difference reported for {missing}", file=sys.stderr)

    total = sum(len(rows) for rows in report.values())
    binds_seed, binds_live = args.binds_seed, args.binds_live

    if args.reset:
        return reset(report, live_paths, binds_seed, binds_live)
    if not args.apply:
        return 1 if total else 0

    for scope in ("settings", "session"):
        rows = [r for r in report[scope] if r["kind"] in ("changed", "new")]
        if not rows:
            continue
        path = seed_paths[scope]
        seed = load_json(path)
        for row in rows:
            if not row.get("live_absent"):
                set_path(seed, row["path"], row["live"])
        # Removing higher list indexes first prevents an earlier deletion from
        # shifting the paths of later absent overrides.
        absent_rows = (row for row in rows if row.get("live_absent"))
        for row in sorted(absent_rows,
                          key=lambda item: path_sort_key(item["path"]),
                          reverse=True):
            delete_path(seed, row["path"])
        path.write_text(json.dumps(seed, indent=2) + "\n")
        # stderr, so --json --apply still emits a single parseable document.
        print(f"updated {path} ({len(rows)} key{'s' if len(rows) != 1 else ''})",
              file=sys.stderr)
    if report.get("keybinds") and binds_seed and binds_live:
        keys = [r["key"] for r in report["keybinds"]]
        saved = write_binds(binds_live, binds_seed, keys)
        print(f"updated {binds_seed} ({len(keys)} bind"
              f"{'s' if len(keys) != 1 else ''}); previous contents saved as "
              f"{saved}", file=sys.stderr)
    stale = [r["key"] for rows in report.values() for r in rows if r["kind"] == "stale"]
    if stale:
        print("left in place (not recognized by the DMS spec; remove by hand if "
              f"intended): {', '.join(stale)}", file=sys.stderr)
    return 0


def backup(path: pathlib.Path) -> pathlib.Path:
    """Copy `path` aside using the same .bak.<epoch> convention as zz refresh."""
    stamp = int(time.time())
    candidate = path.with_name(f"{path.name}.bak.{stamp}")
    suffix = 1
    while candidate.exists():
        candidate = path.with_name(f"{path.name}.bak.{stamp}.{suffix}")
        suffix += 1
    shutil.copy2(path, candidate)
    return candidate


def bind_key_of(line: str) -> str | None:
    """The bind key a KDL line opens, or None if it is not a bind line."""
    stripped = line.strip()
    if not stripped or stripped.startswith("//") or stripped.startswith("}"):
        return None
    if stripped.startswith("binds") or "{" not in stripped:
        return None
    return stripped.split(None, 1)[0]


def index_bind_lines(text: str) -> dict:
    """Map {bind key: (start, end)} line spans within a binds fragment.

    A bind is normally one line, but the span is tracked by brace depth so a
    hand-wrapped multi-line bind is spliced whole rather than truncated.
    """
    lines = text.splitlines(keepends=True)
    spans, index = {}, 0
    while index < len(lines):
        key = bind_key_of(lines[index])
        if key is None:
            index += 1
            continue
        depth, end = 0, index
        while end < len(lines):
            depth += lines[end].count("{") - lines[end].count("}")
            end += 1
            if depth <= 0:
                break
        spans[key] = (index, end)
        index = end
    return spans


def splice_binds(seed_text: str, live_text: str, keys) -> str:
    """Return `seed_text` with only `keys` taken from `live_text`.

    Editing the seed line by line keeps its comments, grouping, and ordering,
    which a whole-file copy from the DMS-rewritten live fragment destroys:
    promoting one rebind should not reflow the file.
    """
    seed_lines = seed_text.splitlines(keepends=True)
    live_lines = live_text.splitlines(keepends=True)
    seed_spans = index_bind_lines(seed_text)
    live_spans = index_bind_lines(live_text)

    edits = []           # (start, end, replacement lines)
    additions = []
    for key in keys:
        replacement = ([]
                       if key not in live_spans
                       else live_lines[slice(*live_spans[key])])
        if key in seed_spans:
            edits.append((*seed_spans[key], replacement))
        elif replacement:
            additions.append(replacement)

    # Apply from the bottom so earlier spans keep their indices.
    for start, end, replacement in sorted(edits, reverse=True):
        seed_lines[start:end] = replacement

    if additions:
        closing = max(i for i, line in enumerate(seed_lines)
                      if line.strip() == "}")
        flat = [line for block in additions for line in block]
        seed_lines[closing:closing] = flat
    return "".join(seed_lines)


def write_binds(source: pathlib.Path, destination: pathlib.Path,
                keys) -> pathlib.Path | None:
    """Splice `keys` from `source` into `destination`, backing it up first."""
    if not destination.exists():
        raise SystemExit(f"missing keybind fragment: {destination}")
    saved = backup(destination)
    destination.write_text(
        splice_binds(destination.read_text(), source.read_text(), keys))
    return saved


def reset(report: dict, live_paths: dict,
          binds_seed: pathlib.Path | None = None,
          binds_live: pathlib.Path | None = None) -> int:
    """Write each reported default back onto the live DMS files.

    DMS holds its settings in memory and rewrites the file on any change, so
    the caller has to restart the shell for this to stick. The IPC setter is
    not an option: it rejects objects and arrays outright, and it assigns
    without running the onChange hooks, so compositor fragments would not be
    regenerated.
    """
    touched = 0
    for scope in ("settings", "session"):
        rows = [r for r in report[scope] if "reset_path" in r]
        if not rows:
            continue
        path = live_paths[scope]
        live = load_json(path)
        saved = backup(path)
        for row in rows:
            set_path(live, row["reset_path"], row["reset_value"])
        path.write_text(json.dumps(live, indent=2) + "\n")
        touched += len(rows)
        print(f"reset {path} ({len(rows)} value{'s' if len(rows) != 1 else ''}); "
              f"previous contents saved as {saved}", file=sys.stderr)
    if report.get("keybinds") and binds_seed and binds_live:
        # niri watches its config, so the restored binds apply without the
        # shell restart that settings.json needs.
        keys = [r["key"] for r in report["keybinds"]]
        saved = write_binds(binds_seed, binds_live, keys)
        touched += len(keys)
        print(f"reset {binds_live} ({len(keys)} bind"
              f"{'s' if len(keys) != 1 else ''}); previous contents saved as "
              f"{saved}", file=sys.stderr)
    if not touched:
        print("Nothing to reset: the live DMS state already matches the "
              "defaults.", file=sys.stderr)
    return 0


def render(report: dict, applying: bool) -> None:
    labels = {
        "changed": "differs from the seed",
        "new": "not in the seed, changed from the DMS default",
        "derived": "rendered by lib/dms.sh, promote by editing the helper",
        "stale": "in the seed but not recognized by the DMS spec",
        "bind-changed": "bound to a different action",
        "bind-added": "not in the seed",
        "bind-removed": "in the seed but no longer bound",
    }
    total = 0
    for scope in SCOPES:
        rows = report[scope]
        if not rows:
            continue
        total += len(rows)
        print(f"\n{scope}:")
        for kind in ("changed", "new", "derived", "stale",
                     "bind-changed", "bind-added", "bind-removed"):
            group = [r for r in rows if r["kind"] == kind]
            if not group:
                continue
            print(f"  {labels[kind]}:")
            for row in group:
                print(f"    {row['key']}")
                if row.get("seed_absent"):
                    print("      seed: (the DMS default carries no such value)")
                else:
                    print(f"      seed: {fmt(row['seed'])}")
                print(f"      live: {fmt(row['live'])}")
                if row.get("helper"):
                    print(f"      promote by editing {row['helper']}() "
                          "in lib/dms.sh")
    if not total:
        print("The live DMS state matches the seeded defaults.")
        return
    if not applying:
        print(f"\n{total} difference{'s' if total != 1 else ''}. "
              "Re-run with --apply to promote them into the seed, or --reset "
              "to restore the defaults onto the live state. Either accepts "
              "KEY [KEY...] for a subset.")


if __name__ == "__main__":
    raise SystemExit(main())
