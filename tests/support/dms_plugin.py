#!/usr/bin/env python3
"""Validate DankMaterialShell plugin directories without third-party modules.

Usage: validate_plugin.py <plugin-dir> [<plugin-dir> ...] [--schema <plugin-schema.json>]

Checks each directory's plugin.json against the rules of the upstream JSON
schema (DMS v1.6.0, bundled next to this script under assets/) and then the
layout mistakes the schema cannot express: referenced QML files that do not
exist, a settings component whose pluginId differs from the manifest id, a
widget or daemon component without the injected popoutService property, a
launcher surface without a trigger, the deprecated `requires` key, and host
paths or machine state that must not ship in a product-owned directory.

Exit status is 1 when any directory has errors; warnings alone exit 0.
The script is self-contained so it can be copied verbatim into
tests/support/ of the ZZ repository.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ID_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9]*$")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$")
QML_PATH_RE = re.compile(r"^\./.*\.qml$")
REQUIRES_DMS_RE = re.compile(r"^(>=?|<=?|=|>|<)\d+\.\d+\.\d+$")
HOME_PATH_RE = re.compile(r"/home/[A-Za-z0-9._-]+/")
TYPES = ("widget", "daemon", "launcher", "desktop", "composite")
SURFACES = ("widget", "desktop", "daemon", "launcher")
PERMISSIONS = ("settings_read", "settings_write", "process", "network")
REQUIRED = ("id", "name", "description", "version", "author", "type", "capabilities")


class Report:
    def __init__(self, where: str) -> None:
        self.where = where
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


def load_schema(path: Path | None) -> dict | None:
    candidates = [path] if path else []
    here = Path(__file__).resolve().parent
    # Skill layout (scripts/ next to assets/) and the in-repo copy under
    # tests/support/, where the schema sits beside the script.
    candidates.append(here.parent / "assets" / "plugin-schema.json")
    candidates.append(here / "plugin-schema.json")
    for candidate in candidates:
        if candidate and candidate.is_file():
            with candidate.open(encoding="utf-8") as handle:
                return json.load(handle)
    return None


def check_string(report: Report, manifest: dict, key: str, pattern: re.Pattern | None = None) -> str | None:
    value = manifest.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        report.error(f"'{key}' must be a string")
        return None
    if not value.strip():
        report.error(f"'{key}' must not be empty")
        return None
    if pattern and not pattern.match(value):
        report.error(f"'{key}' does not match {pattern.pattern}: {value!r}")
        return None
    return value


def check_string_list(report: Report, manifest: dict, key: str, allowed: tuple[str, ...] | None = None) -> list[str]:
    value = manifest.get(key)
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        report.error(f"'{key}' must be an array of strings")
        return []
    if allowed:
        for item in value:
            if item not in allowed:
                report.error(f"'{key}' contains unknown value {item!r}; allowed: {', '.join(allowed)}")
    return value


def resolve(plugin_dir: Path, relative: str) -> Path:
    return plugin_dir / relative[2:] if relative.startswith("./") else plugin_dir / relative


def component_paths(report: Report, manifest: dict) -> dict[str, str]:
    """Return surface -> relative path, mirroring PluginService._resolveComponentPaths."""
    paths: dict[str, str] = {}
    has_component = "component" in manifest
    has_components = "components" in manifest
    if has_component and has_components:
        report.error("provide either 'component' or 'components', not both")
    if not has_component and not has_components:
        report.error("one of 'component' or 'components' is required")
        return paths

    plugin_type = manifest.get("type")
    if has_component:
        value = check_string(report, manifest, "component", QML_PATH_RE)
        if value:
            surface = plugin_type if plugin_type in SURFACES else "widget"
            paths[surface] = value
    if has_components:
        components = manifest["components"]
        if not isinstance(components, dict) or not components:
            report.error("'components' must be a non-empty object")
            return paths
        for surface, value in components.items():
            if surface not in SURFACES:
                report.error(f"'components' has unknown surface {surface!r}; allowed: {', '.join(SURFACES)}")
                continue
            if not isinstance(value, str) or not QML_PATH_RE.match(value):
                report.error(f"'components.{surface}' must be a ./path.qml string")
                continue
            paths[surface] = value
    return paths


def scan_qml(report: Report, path: Path, label: str) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        report.error(f"{label}: cannot read {path.name}: {exc}")
        return ""
    if HOME_PATH_RE.search(text):
        report.error(f"{label}: {path.name} embeds a /home/<user>/ path; derive paths at runtime instead")
    return text


def validate_manifest(report: Report, plugin_dir: Path, manifest: dict) -> None:
    for key in REQUIRED:
        if key not in manifest:
            report.error(f"missing required key '{key}'")

    plugin_id = check_string(report, manifest, "id", ID_RE)
    check_string(report, manifest, "name")
    check_string(report, manifest, "description")
    check_string(report, manifest, "version", SEMVER_RE)
    check_string(report, manifest, "author")
    plugin_type = check_string(report, manifest, "type")
    if plugin_type and plugin_type not in TYPES:
        report.error(f"'type' must be one of {', '.join(TYPES)}; got {plugin_type!r}")

    capabilities = manifest.get("capabilities")
    if capabilities is not None:
        if not isinstance(capabilities, list) or not all(isinstance(c, str) for c in capabilities):
            report.error("'capabilities' must be an array of strings")
        elif not capabilities:
            report.error("'capabilities' must list at least one capability")

    check_string(report, manifest, "icon")
    check_string(report, manifest, "requires_dms", REQUIRES_DMS_RE)
    check_string_list(report, manifest, "dependencies")
    permissions = check_string_list(report, manifest, "permissions", PERMISSIONS)
    if "requires" in manifest:
        check_string_list(report, manifest, "requires")
        report.warn("'requires' is deprecated; rename it to 'dependencies'")

    paths = component_paths(report, manifest)
    if plugin_type == "composite" and "components" not in manifest:
        report.warn("type 'composite' normally pairs with a 'components' map")

    needs_trigger = plugin_type == "launcher" or "launcher" in paths
    trigger = manifest.get("trigger")
    if needs_trigger:
        if not isinstance(trigger, str):
            report.error("a launcher surface requires a 'trigger' string")
    elif trigger is not None and not isinstance(trigger, str):
        report.error("'trigger' must be a string")

    settings_rel = check_string(report, manifest, "settings", QML_PATH_RE) if "settings" in manifest else None
    if settings_rel and "settings_write" not in permissions:
        report.error("a 'settings' component requires the 'settings_write' permission")

    startup_rel = check_string(report, manifest, "startupCheck", QML_PATH_RE) if "startupCheck" in manifest else None

    # Files on disk.
    for surface, rel in paths.items():
        path = resolve(plugin_dir, rel)
        if not path.is_file():
            report.error(f"{surface} component {rel} does not exist")
            continue
        text = scan_qml(report, path, f"{surface} component")
        if surface in ("widget", "daemon"):
            if "PluginComponent" not in text:
                report.warn(f"{surface} component {rel} does not use PluginComponent")
            # WidgetHost injects PopoutService only into items that declare the
            # property; PluginComponent does not declare it, so a plugin that
            # calls popoutService without declaring it always sees null.
            if re.search(r"\bpopoutService\s*[.?]", text) and not re.search(r"property\s+var\s+popoutService", text):
                report.error(f"{surface} component {rel} uses popoutService without declaring 'property var popoutService: null'")
            if surface == "widget" and "horizontalBarPill" in text and "verticalBarPill" not in text:
                report.warn(f"widget component {rel} defines horizontalBarPill but no verticalBarPill; it disappears on a side-anchored bar")
        if surface == "launcher":
            if "PluginComponent" in text:
                report.warn(f"launcher component {rel} uses PluginComponent; launchers are plain Items")
            for fn in ("getItems", "executeItem"):
                if f"function {fn}" not in text:
                    report.error(f"launcher component {rel} must define function {fn}(...)")
        if surface == "desktop":
            # DesktopPluginComponent declares pluginService/pluginId itself; a
            # plain Item must declare them to receive the injection.
            if "DesktopPluginComponent" not in text and not re.search(r"property\s+var\s+pluginService", text):
                report.warn(f"desktop component {rel} is a plain Item without 'property var pluginService: null'")

    if settings_rel:
        path = resolve(plugin_dir, settings_rel)
        if not path.is_file():
            report.error(f"settings component {settings_rel} does not exist")
        else:
            text = scan_qml(report, path, "settings component")
            match = re.search(r"pluginId\s*:\s*\"([^\"]+)\"", text)
            if match and plugin_id and match.group(1) != plugin_id:
                report.error(f"settings component declares pluginId {match.group(1)!r} but the manifest id is {plugin_id!r}")
            elif not match and "PluginSettings" in text:
                report.warn("settings component uses PluginSettings without a literal pluginId")

    if startup_rel:
        path = resolve(plugin_dir, startup_rel)
        if not path.is_file():
            report.error(f"startupCheck component {startup_rel} does not exist")
        else:
            text = scan_qml(report, path, "startupCheck component")
            if "function check" not in text:
                report.error(f"startupCheck component {startup_rel} must define function check(done)")

    # Translation files, if present, must be JSON objects.
    translations = plugin_dir / "translations"
    if translations.is_dir():
        for tr in sorted(translations.glob("*.json")):
            if tr.name == "en.json":
                report.warn("translations/en.json is ignored; English strings come from the QML terms")
            try:
                data = json.loads(tr.read_text(encoding="utf-8"))
            except (OSError, ValueError) as exc:
                report.error(f"translations/{tr.name} is not valid JSON: {exc}")
                continue
            if not isinstance(data, dict):
                report.error(f"translations/{tr.name} must be a JSON object")

    # Product-owned directories must not carry machine state.
    for name in ("plugin_settings.json", "settings.json", "session.json"):
        if (plugin_dir / name).exists():
            report.error(f"{name} is DMS user/state data and must not ship with the plugin")


def validate_dir(plugin_dir: Path, schema: dict | None) -> Report:
    report = Report(str(plugin_dir))
    if not plugin_dir.is_dir():
        report.error("not a directory")
        return report
    if not re.match(r"^[A-Z][A-Za-z0-9]*$", plugin_dir.name):
        report.warn(f"directory name {plugin_dir.name!r} is not PascalCase")
    manifest_path = plugin_dir / "plugin.json"
    if not manifest_path.is_file():
        report.error("plugin.json is missing")
        return report
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except ValueError as exc:
        report.error(f"plugin.json is not valid JSON: {exc}")
        return report
    if not isinstance(manifest, dict):
        report.error("plugin.json must contain a JSON object")
        return report

    if schema:
        # Guard against silent drift: every property the schema knows should
        # be covered by this validator's rules. Unknown extra keys are allowed
        # by the schema (additionalProperties: true) and only warned about.
        known = set(schema.get("properties", {}))
        for key in manifest:
            if key not in known:
                report.warn(f"manifest key {key!r} is not in the schema (allowed, but check the spelling)")

    validate_manifest(report, plugin_dir, manifest)
    return report


def main(argv: list[str]) -> int:
    schema_path: Path | None = None
    dirs: list[Path] = []
    args = iter(argv)
    for arg in args:
        if arg == "--schema":
            schema_path = Path(next(args, ""))
        elif arg in ("-h", "--help"):
            print(__doc__.strip())
            return 0
        else:
            dirs.append(Path(arg))
    if not dirs:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    schema = load_schema(schema_path)
    failed = False
    for plugin_dir in dirs:
        report = validate_dir(plugin_dir.resolve(), schema)
        status = "FAIL" if report.errors else "ok"
        print(f"{status}: {report.where}")
        for message in report.errors:
            print(f"  error: {message}")
        for message in report.warnings:
            print(f"  warning: {message}")
        failed = failed or bool(report.errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
