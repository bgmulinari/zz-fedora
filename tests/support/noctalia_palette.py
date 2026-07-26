#!/usr/bin/env python3
"""Validate managed Noctalia fixed palettes and their paired color contrast."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


MIN_CONTRAST = 4.5
HEX_COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
ROLE_KEYS = (
    "mPrimary",
    "mOnPrimary",
    "mSecondary",
    "mOnSecondary",
    "mTertiary",
    "mOnTertiary",
    "mError",
    "mOnError",
    "mSurface",
    "mOnSurface",
    "mSurfaceVariant",
    "mOnSurfaceVariant",
    "mOutline",
    "mShadow",
    "mHover",
    "mOnHover",
)
ROLE_PAIRS = (
    ("mPrimary", "mOnPrimary"),
    ("mSecondary", "mOnSecondary"),
    ("mTertiary", "mOnTertiary"),
    ("mError", "mOnError"),
    ("mSurface", "mOnSurface"),
    ("mSurfaceVariant", "mOnSurfaceVariant"),
    ("mHover", "mOnHover"),
)
TERMINAL_KEYS = (
    "background",
    "foreground",
    "cursor",
    "cursorText",
    "selectionBg",
    "selectionFg",
)
TERMINAL_PAIRS = (
    ("background", "foreground"),
    ("cursor", "cursorText"),
    ("selectionBg", "selectionFg"),
)
ANSI_KEYS = ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def require_color(table: dict, key: str, context: str) -> str:
    value = table.get(key)
    if not isinstance(value, str) or not HEX_COLOR.fullmatch(value):
        fail(f"{context}.{key} must be a six-digit hex color, got {value!r}")
    return value


def linear_channel(value: float) -> float:
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def luminance(color: str) -> float:
    channels = [int(color[index : index + 2], 16) / 255 for index in (1, 3, 5)]
    red, green, blue = (linear_channel(channel) for channel in channels)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def contrast(first: str, second: str) -> float:
    lighter, darker = sorted((luminance(first), luminance(second)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def validate_pairs(table: dict, pairs: tuple[tuple[str, str], ...], context: str) -> None:
    for background_key, foreground_key in pairs:
        background = require_color(table, background_key, context)
        foreground = require_color(table, foreground_key, context)
        ratio = contrast(background, foreground)
        if ratio < MIN_CONTRAST:
            fail(
                f"{context} {background_key}/{foreground_key} contrast is "
                f"{ratio:.2f}:1; expected at least {MIN_CONTRAST:.1f}:1"
            )


def validate_mode(mode: dict, context: str) -> None:
    for key in ROLE_KEYS:
        require_color(mode, key, context)
    validate_pairs(mode, ROLE_PAIRS, context)

    terminal = mode.get("terminal")
    if not isinstance(terminal, dict):
        fail(f"{context}.terminal must be an object")
    for key in TERMINAL_KEYS:
        require_color(terminal, key, f"{context}.terminal")
    validate_pairs(terminal, TERMINAL_PAIRS, f"{context}.terminal")

    for group_name in ("normal", "bright"):
        group = terminal.get(group_name)
        if not isinstance(group, dict):
            fail(f"{context}.terminal.{group_name} must be an object")
        for key in ANSI_KEYS:
            require_color(group, key, f"{context}.terminal.{group_name}")


def validate_palette(path: Path) -> None:
    try:
        root = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        fail(f"{path}: cannot read palette: {error}")
    if not isinstance(root, dict):
        fail(f"{path}: palette root must be an object")
    if not isinstance(root.get("dark"), dict):
        fail(f"{path}: palette must include a dark object")
    for mode_name in ("dark", "light"):
        mode = root.get(mode_name)
        if mode is not None:
            if not isinstance(mode, dict):
                fail(f"{path}: {mode_name} must be an object")
            validate_mode(mode, f"{path.name}.{mode_name}")


def main() -> None:
    if len(sys.argv) < 2:
        fail("usage: noctalia_palette.py <palette.json> [...]")
    for argument in sys.argv[1:]:
        validate_palette(Path(argument))


if __name__ == "__main__":
    main()
