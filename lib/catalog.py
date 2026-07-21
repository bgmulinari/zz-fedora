#!/usr/bin/env python3
"""Catalog compiler for the zz-fedora installer.

The data-driven installer API lives under catalog/ as one TOML file per
unit plus one TOML file per software source. This tool is the single
authority on that format: it validates the whole catalog and compiles it
into flat tab-separated files that the Bash installer consumes.

Subcommands:
  validate            Validate the catalog and report every error.
  compile --out DIR   Validate, then write the compiled TSV files.

Catalog layout: catalog/units/<group>/<name>.toml holds one unit per file
(group directories are organizational; [base] and [choice] tables carry the
semantics, and only catalog/units/base/ requires a [base] table), while
catalog/sources/<kind>/<name>.toml holds one software source per file.

The compiled layout under --out:
  bundles.tsv           id, base, base_order, early, minimal_skip,
                        requires, sources, stow, backends, description
  base.tsv              id, early, minimal_skip — base units in base order
  steps.tsv             bundle_id, step_index, backend, sources
  items.tsv             bundle_id, step_index, backend, item
  sources.tsv           id, kind, label, project, required, gpg_policy,
                        bootstrap_exception, description, reason
  choices/<cat>.tsv     choice_id, label, default, units, description
  categories.list       one category name per line

List-valued TSV fields are comma-joined; boolean fields are 0/1. String
fields must not contain tabs or newlines, which validation enforces.

Requires Python >= 3.11 (tomllib). No third-party dependencies.
"""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

SOURCE_KINDS = (
    "official",
    "copr",
    "terra",
    "rpmfusion",
    "cisco-openh264",
    "vendor",
    "flatpak",
    "artifact",
)

GPG_POLICIES = (
    "distro-managed",
    "copr-plugin",
    "rpm-gpg-import",
    "repo-gpg-key",
    "flatpak-gpg",
    "unsigned-bootstrap",
    "pinned-commit",
    "sha256",
    "tls-only",
)

BACKENDS = ("dnf", "flatpak", "action")

# Each install step names its payload with a backend-specific key.
BACKEND_ITEM_KEY = {"dnf": "packages", "flatpak": "flatpaks", "action": "actions"}

UNIT_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]+$")
SOURCE_ID_RE = re.compile(r"^[A-Za-z0-9_.:/-]+$")
CHOICE_ID_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
CATEGORY_RE = re.compile(r"^[a-z0-9-]+$")
CATEGORY_ALIASES = {"browser": "browsers", "source": "sources"}

UNIT_KEYS = {"id", "description", "requires", "stow", "base", "choice", "install"}
BASE_KEYS = {"order", "early", "minimal_desktop_skip"}
CHOICE_KEYS = {"category", "id", "label", "default", "order", "description", "also"}
INSTALL_KEYS = {"backend", "sources", "packages", "flatpaks", "actions"}
SOURCE_KEYS = {
    "id",
    "kind",
    "label",
    "project",
    "required",
    "description",
    "gpg_policy",
    "bootstrap_exception",
    "reason",
}


class Errors:
    def __init__(self) -> None:
        self.messages: list[str] = []

    def add(self, where: str, message: str) -> None:
        self.messages.append(f"{where}: {message}")

    def bail_if_any(self) -> None:
        if self.messages:
            for message in self.messages:
                print(f"catalog error: {message}", file=sys.stderr)
            print(
                f"catalog validation failed with {len(self.messages)} error(s)",
                file=sys.stderr,
            )
            sys.exit(1)


def clean_string(errors: Errors, where: str, key: str, value: object) -> str:
    if not isinstance(value, str):
        errors.add(where, f"'{key}' must be a string")
        return ""
    if "\t" in value or "\n" in value:
        errors.add(where, f"'{key}' must not contain tabs or newlines")
        return ""
    return value


def required_string(errors: Errors, where: str, table: dict, key: str) -> str:
    if key not in table:
        errors.add(where, f"missing required key '{key}'")
        return ""
    value = clean_string(errors, where, key, table[key])
    if isinstance(table[key], str) and not value.strip():
        errors.add(where, f"'{key}' must not be empty")
        return ""
    return value


def optional_bool(errors: Errors, where: str, table: dict, key: str, default: bool = False) -> bool:
    if key not in table:
        return default
    value = table[key]
    if not isinstance(value, bool):
        errors.add(where, f"'{key}' must be a boolean")
        return default
    return value


def optional_int(errors: Errors, where: str, table: dict, key: str, default: int) -> int:
    if key not in table:
        return default
    value = table[key]
    if not isinstance(value, int) or isinstance(value, bool):
        errors.add(where, f"'{key}' must be an integer")
        return default
    return value


def string_list(errors: Errors, where: str, table: dict, key: str) -> list[str]:
    if key not in table:
        return []
    value = table[key]
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        errors.add(where, f"'{key}' must be an array of strings")
        return []
    cleaned: list[str] = []
    for item in value:
        item_clean = clean_string(errors, where, key, item)
        if not item_clean.strip():
            errors.add(where, f"'{key}' must not contain empty entries")
            continue
        if "," in item_clean:
            errors.add(where, f"'{key}' entries must not contain commas")
            continue
        if item_clean in cleaned:
            errors.add(where, f"duplicate '{key}' entry: {item_clean}")
            continue
        cleaned.append(item_clean)
    return cleaned


def reject_unknown_keys(errors: Errors, where: str, table: dict, allowed: set[str]) -> None:
    for key in table:
        if key not in allowed:
            errors.add(where, f"unknown key '{key}'")


def load_toml(errors: Errors, path: Path) -> dict | None:
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except tomllib.TOMLDecodeError as exc:
        errors.add(str(path), f"invalid TOML: {exc}")
        return None
    except OSError as exc:
        errors.add(str(path), f"unreadable: {exc}")
        return None


class Source:
    def __init__(self, path: Path, table: dict, errors: Errors) -> None:
        where = str(path)
        reject_unknown_keys(errors, where, table, SOURCE_KEYS)
        self.path = path
        self.id = required_string(errors, where, table, "id")
        self.kind = required_string(errors, where, table, "kind")
        self.label = required_string(errors, where, table, "label")
        self.description = required_string(errors, where, table, "description")
        self.gpg_policy = required_string(errors, where, table, "gpg_policy")
        self.reason = required_string(errors, where, table, "reason")
        self.required = optional_bool(errors, where, table, "required")
        self.bootstrap_exception = optional_bool(errors, where, table, "bootstrap_exception")
        self.project = clean_string(errors, where, "project", table.get("project", ""))

        if self.id and not SOURCE_ID_RE.match(self.id):
            errors.add(where, f"invalid source id '{self.id}'")
        if self.kind and self.kind not in SOURCE_KINDS:
            errors.add(where, f"unsupported source kind '{self.kind}'")
        if self.gpg_policy and self.gpg_policy not in GPG_POLICIES:
            errors.add(where, f"invalid gpg_policy '{self.gpg_policy}'")
        if self.gpg_policy == "unsigned-bootstrap" and not self.bootstrap_exception:
            errors.add(where, "unsigned-bootstrap sources must set bootstrap_exception = true")
        if self.kind in ("copr", "artifact"):
            if not self.project.strip():
                errors.add(where, f"'project' is required for {self.kind} sources")
        elif self.project:
            errors.add(where, "'project' is only valid for copr and artifact sources")


class InstallStep:
    def __init__(self, path: Path, index: int, table: dict, errors: Errors) -> None:
        where = f"{path} [install #{index + 1}]"
        reject_unknown_keys(errors, where, table, INSTALL_KEYS)
        self.index = index
        self.backend = required_string(errors, where, table, "backend")
        self.sources = string_list(errors, where, table, "sources")
        self.items: list[str] = []

        if self.backend and self.backend not in BACKENDS:
            errors.add(where, f"unsupported backend '{self.backend}'")
            return
        for backend, key in BACKEND_ITEM_KEY.items():
            if key in table and backend != self.backend:
                errors.add(where, f"'{key}' is only valid for backend = \"{backend}\"")
        item_key = BACKEND_ITEM_KEY.get(self.backend)
        if item_key:
            self.items = string_list(errors, where, table, item_key)


class Unit:
    def __init__(self, path: Path, table: dict, errors: Errors) -> None:
        where = str(path)
        reject_unknown_keys(errors, where, table, UNIT_KEYS)
        self.path = path
        self.id = required_string(errors, where, table, "id")
        self.description = required_string(errors, where, table, "description")
        self.requires = string_list(errors, where, table, "requires")
        self.stow = string_list(errors, where, table, "stow")
        self.base: dict | None = None
        self.choice: dict | None = None
        self.steps: list[InstallStep] = []

        if self.id and not UNIT_ID_RE.match(self.id):
            errors.add(where, f"invalid unit id '{self.id}'")
        if self.id in self.requires:
            errors.add(where, f"unit '{self.id}' cannot require itself")

        base_table = table.get("base")
        if base_table is not None:
            if not isinstance(base_table, dict):
                errors.add(where, "[base] must be a table")
            else:
                base_where = f"{where} [base]"
                reject_unknown_keys(errors, base_where, base_table, BASE_KEYS)
                order = base_table.get("order")
                if not isinstance(order, int) or isinstance(order, bool) or order < 0:
                    errors.add(base_where, "'order' must be a non-negative integer")
                    order = 0
                self.base = {
                    "order": order,
                    "early": optional_bool(errors, base_where, base_table, "early"),
                    "minimal_desktop_skip": optional_bool(
                        errors, base_where, base_table, "minimal_desktop_skip"
                    ),
                }

        choice_table = table.get("choice")
        if choice_table is not None:
            if not isinstance(choice_table, dict):
                errors.add(where, "[choice] must be a table")
            else:
                choice_where = f"{where} [choice]"
                reject_unknown_keys(errors, choice_where, choice_table, CHOICE_KEYS)
                self.choice = {
                    "category": required_string(errors, choice_where, choice_table, "category"),
                    "id": required_string(errors, choice_where, choice_table, "id"),
                    "label": required_string(errors, choice_where, choice_table, "label"),
                    "description": required_string(errors, choice_where, choice_table, "description"),
                    "default": optional_bool(errors, choice_where, choice_table, "default"),
                    "order": optional_int(errors, choice_where, choice_table, "order", 100),
                    "also": string_list(errors, choice_where, choice_table, "also"),
                }
                category = self.choice["category"]
                if category and not CATEGORY_RE.match(category):
                    errors.add(choice_where, f"invalid category '{category}'")
                elif category in CATEGORY_ALIASES:
                    errors.add(
                        choice_where,
                        f"category '{category}' is a runtime alias; "
                        f"use '{CATEGORY_ALIASES[category]}'",
                    )
                if self.choice["id"] and not CHOICE_ID_RE.match(self.choice["id"]):
                    errors.add(choice_where, f"invalid choice id '{self.choice['id']}'")

        if self.base is not None and self.choice is not None:
            errors.add(where, "a unit cannot declare both [base] and [choice]")

        install_tables = table.get("install")
        if install_tables is None:
            errors.add(where, "at least one [[install]] step is required")
        elif not isinstance(install_tables, list) or not all(
            isinstance(step, dict) for step in install_tables
        ):
            errors.add(where, "[[install]] must be an array of tables")
        else:
            if not install_tables:
                errors.add(where, "at least one [[install]] step is required")
            for index, step_table in enumerate(install_tables):
                self.steps.append(InstallStep(path, index, step_table, errors))

    @property
    def sources(self) -> list[str]:
        merged: list[str] = []
        for step in self.steps:
            for source_id in step.sources:
                if source_id not in merged:
                    merged.append(source_id)
        return merged

    @property
    def backends(self) -> list[str]:
        merged: list[str] = []
        for step in self.steps:
            if step.backend and step.backend not in merged:
                merged.append(step.backend)
        return merged


class Catalog:
    def __init__(self, root: Path, errors: Errors) -> None:
        self.root = root
        self.errors = errors
        self.sources: dict[str, Source] = {}
        self.units: dict[str, Unit] = {}
        self.load()
        self.validate_references()

    def catalog_dir(self) -> Path:
        return self.root / "catalog"

    def load(self) -> None:
        catalog_dir = self.catalog_dir()
        if not catalog_dir.is_dir():
            self.errors.add(str(catalog_dir), "catalog directory not found")
            return

        source_dir = catalog_dir / "sources"
        for path in sorted(source_dir.rglob("*.toml")) if source_dir.is_dir() else []:
            table = load_toml(self.errors, path)
            if table is None:
                continue
            source = Source(path, table, self.errors)
            if not source.id:
                continue
            if source.id in self.sources:
                self.errors.add(
                    str(path),
                    f"duplicate source id '{source.id}' (also in {self.sources[source.id].path})",
                )
                continue
            self.sources[source.id] = source

        units_dir = catalog_dir / "units"
        if not units_dir.is_dir():
            self.errors.add(str(units_dir), "catalog units directory not found")
            return
        for path in sorted(units_dir.rglob("*.toml")):
            table = load_toml(self.errors, path)
            if table is None:
                continue
            unit = Unit(path, table, self.errors)
            if not unit.id:
                continue
            if unit.id in self.units:
                self.errors.add(
                    str(path),
                    f"duplicate unit id '{unit.id}' (also in {self.units[unit.id].path})",
                )
                continue
            if (units_dir / "base") in path.parents and unit.base is None:
                self.errors.add(
                    str(path), "units under catalog/units/base/ must declare a [base] table"
                )
            self.units[unit.id] = unit

    def validate_references(self) -> None:
        base_orders: dict[int, str] = {}
        choice_ids: dict[tuple[str, str], str] = {}

        for unit in self.units.values():
            where = str(unit.path)
            for dependency in unit.requires:
                if dependency not in self.units:
                    self.errors.add(where, f"unknown required unit '{dependency}'")
            for step in unit.steps:
                for source_id in step.sources:
                    if source_id not in self.sources:
                        self.errors.add(where, f"unknown source id '{source_id}'")
                if step.backend in BACKENDS and not step.items and not step.sources:
                    item_key = BACKEND_ITEM_KEY[step.backend]
                    self.errors.add(
                        where,
                        f"install step #{step.index + 1} has no {item_key} and no sources",
                    )
            if unit.base is not None:
                order = unit.base["order"]
                if order in base_orders:
                    self.errors.add(
                        where,
                        f"duplicate base order {order} (also used by '{base_orders[order]}')",
                    )
                else:
                    base_orders[order] = unit.id
            if unit.choice is not None:
                key = (unit.choice["category"], unit.choice["id"])
                if all(key):
                    if key in choice_ids:
                        self.errors.add(
                            where,
                            f"duplicate choice '{key[1]}' in category '{key[0]}' "
                            f"(also declared by '{choice_ids[key]}')",
                        )
                    else:
                        choice_ids[key] = unit.id
                for extra in unit.choice["also"]:
                    extra_unit = self.units.get(extra)
                    if extra_unit is None:
                        self.errors.add(where, f"unknown unit '{extra}' in [choice] also")
                    elif extra_unit.base is not None:
                        self.errors.add(
                            where, f"base unit '{extra}' must not be selected by a choice"
                        )

    def base_units_in_order(self) -> list[Unit]:
        base_units = [unit for unit in self.units.values() if unit.base is not None]
        return sorted(base_units, key=lambda unit: unit.base["order"])

    def categories(self) -> dict[str, list[Unit]]:
        grouped: dict[str, list[Unit]] = {}
        for unit in self.units.values():
            if unit.choice is None:
                continue
            grouped.setdefault(unit.choice["category"], []).append(unit)
        for units in grouped.values():
            units.sort(key=lambda unit: (unit.choice["order"], unit.choice["id"]))
        return dict(sorted(grouped.items()))


def flag(value: bool) -> str:
    return "1" if value else "0"


def compile_catalog(catalog: Catalog, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "choices").mkdir(exist_ok=True)

    bundle_rows: list[str] = []
    step_rows: list[str] = []
    item_rows: list[str] = []
    for unit_id in sorted(catalog.units):
        unit = catalog.units[unit_id]
        base = unit.base or {}
        bundle_rows.append(
            "\t".join(
                (
                    unit.id,
                    flag(unit.base is not None),
                    str(base["order"]) if unit.base is not None else "",
                    flag(bool(base.get("early"))),
                    flag(bool(base.get("minimal_desktop_skip"))),
                    ",".join(unit.requires),
                    ",".join(unit.sources),
                    ",".join(unit.stow),
                    ",".join(unit.backends),
                    unit.description,
                )
            )
        )
        for step in unit.steps:
            step_rows.append(
                "\t".join((unit.id, str(step.index), step.backend, ",".join(step.sources)))
            )
            for item in sorted(step.items):
                item_rows.append("\t".join((unit.id, str(step.index), step.backend, item)))

    source_rows: list[str] = []
    for source_id in sorted(catalog.sources):
        source = catalog.sources[source_id]
        source_rows.append(
            "\t".join(
                (
                    source.id,
                    source.kind,
                    source.label,
                    source.project,
                    flag(source.required),
                    source.gpg_policy,
                    flag(source.bootstrap_exception),
                    source.description,
                    source.reason,
                )
            )
        )

    base_rows = [
        "\t".join(
            (
                unit.id,
                flag(bool(unit.base.get("early"))),
                flag(bool(unit.base.get("minimal_desktop_skip"))),
            )
        )
        for unit in catalog.base_units_in_order()
    ]

    write_lines(out_dir / "bundles.tsv", bundle_rows)
    write_lines(out_dir / "base.tsv", base_rows)
    write_lines(out_dir / "steps.tsv", step_rows)
    write_lines(out_dir / "items.tsv", item_rows)
    write_lines(out_dir / "sources.tsv", source_rows)

    categories = catalog.categories()
    for stale in (out_dir / "choices").glob("*.tsv"):
        if stale.stem not in categories:
            stale.unlink()
    for category, units in categories.items():
        rows = []
        for unit in units:
            choice = unit.choice
            selected_units = [unit.id, *choice["also"]]
            rows.append(
                "\t".join(
                    (
                        choice["id"],
                        choice["label"],
                        flag(choice["default"]),
                        ",".join(selected_units),
                        choice["description"],
                    )
                )
            )
        write_lines(out_dir / "choices" / f"{category}.tsv", rows)
    write_lines(out_dir / "categories.list", list(categories))


def write_lines(path: Path, lines: list[str]) -> None:
    content = "".join(f"{line}\n" for line in lines)
    path.write_text(content, encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root containing catalog/ (default: this checkout)",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate", help="validate the catalog")
    compile_parser = subparsers.add_parser("compile", help="validate and compile the catalog")
    compile_parser.add_argument("--out", type=Path, required=True, help="output directory")
    args = parser.parse_args(argv)

    errors = Errors()
    catalog = Catalog(args.root, errors)
    errors.bail_if_any()

    if args.command == "compile":
        compile_catalog(catalog, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
