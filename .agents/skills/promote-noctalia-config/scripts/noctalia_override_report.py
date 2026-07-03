#!/usr/bin/env python3
"""Report Noctalia state overrides relative to the managed repo dotfile."""

from __future__ import annotations

import argparse
import re
import tomllib
from pathlib import Path
from typing import Any


DEFAULT_MANAGED = Path("dotfiles/noctalia/.config/noctalia/config.toml")
DEFAULT_STATE = Path.home() / ".local/state/noctalia/settings.toml"

HARDWARE_PREFIXES = (
    "lockscreen_widgets.",
    "desktop_widgets.",
)
HARDWARE_PATTERNS = (
    re.compile(r"(^|\.)(output|cx|cy|box_width|box_height|rotation)$"),
    re.compile(r"\.monitor\."),
    re.compile(r"(^|\.)monitors$"),
)


def load_toml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("rb") as handle:
        return tomllib.load(handle)


def flatten(value: Any, prefix: str = "") -> dict[str, Any]:
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        for key, child in value.items():
            child_prefix = f"{prefix}.{key}" if prefix else str(key)
            out.update(flatten(child, child_prefix))
        return out
    return {prefix: value}


def value_text(value: Any) -> str:
    if isinstance(value, str):
        return f'"{value}"'
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return "[ " + ", ".join(value_text(item) for item in value) + " ]"
    return repr(value)


def is_hardware_key(key: str) -> bool:
    if key.startswith(HARDWARE_PREFIXES):
        return True
    return any(pattern.search(key) for pattern in HARDWARE_PATTERNS)


def print_section(title: str, rows: list[str]) -> None:
    print(f"\n## {title}")
    if not rows:
        print("- none")
        return
    for row in rows:
        print(f"- {row}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--managed", type=Path, default=DEFAULT_MANAGED)
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE)
    parser.add_argument(
        "--show-local",
        action="store_true",
        help="Print hardware/local state keys that are excluded from promotion candidates.",
    )
    args = parser.parse_args()

    managed_path = args.managed.expanduser()
    state_path = args.state.expanduser()
    managed = flatten(load_toml(managed_path))
    state = flatten(load_toml(state_path))

    print(f"Managed config: {managed_path}")
    print(f"State overrides: {state_path}")

    overrides: list[str] = []
    portable_state_only: list[str] = []
    hardware: list[str] = []
    redundant: list[str] = []

    for key in sorted(state):
        state_value = state[key]
        if is_hardware_key(key):
            hardware.append(f"{key} = {value_text(state_value)}")
            continue
        if key in managed:
            managed_value = managed[key]
            if state_value == managed_value:
                redundant.append(f"{key} = {value_text(state_value)}")
            else:
                overrides.append(
                    f"{key}: managed {value_text(managed_value)} -> state {value_text(state_value)}"
                )
            continue
        portable_state_only.append(f"{key} = {value_text(state_value)}")

    print_section("Overrides managed dotfile", overrides)
    print_section("State-only portable candidates", portable_state_only)
    print_section("Redundant state keys", redundant)
    print(f"\n## Hardware/local state")
    if not hardware:
        print("- none")
    elif args.show_local:
        for row in hardware:
            print(f"- {row}")
    else:
        print(f"- {len(hardware)} excluded key(s); pass --show-local to print them")

    if state and not (overrides or portable_state_only):
        print("\nNo portable overrides found. State currently contains only redundant or local/generated data.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
