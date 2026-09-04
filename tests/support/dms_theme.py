#!/usr/bin/env python3
"""Validate the vendored DMS Catppuccin registry theme.

Checks the structure the shell's Theme loader consumes (flavors, accents,
hex colors) and WCAG contrast: AA text contrast (4.5:1) for every flavor's
surface and background text pairs, and non-text UI contrast (3:1) for the
shipped blue accent's primary pair in every flavor.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

MIN_TEXT_CONTRAST = 4.5
MIN_UI_CONTRAST = 3.0
SHIPPED_ACCENT = "blue"
EXPECTED_FLAVORS = {"mocha", "macchiato", "frappe", "latte"}
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
REQUIRED_FLAVOR_KEYS = {
    "surface",
    "surfaceText",
    "surfaceVariant",
    "surfaceVariantText",
    "background",
    "backgroundText",
    "outline",
    "error",
}
REQUIRED_ACCENT_KEYS = {"primary", "primaryText", "secondary"}


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def rgb(hex_color: str) -> tuple[float, float, float]:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[index : index + 2], 16) / 255 for index in (0, 2, 4))


def linear_channel(value: float) -> float:
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def luminance(hex_color: str) -> float:
    red, green, blue = rgb(hex_color)
    return 0.2126 * linear_channel(red) + 0.7152 * linear_channel(green) + 0.0722 * linear_channel(blue)


def contrast(first: str, second: str) -> float:
    lighter = max(luminance(first), luminance(second))
    darker = min(luminance(first), luminance(second))
    return (lighter + 0.05) / (darker + 0.05)


def require_hex_values(table: dict, keys: set[str], context: str) -> None:
    for key in sorted(keys):
        value = table.get(key)
        if not isinstance(value, str) or not HEX_RE.fullmatch(value):
            fail(f"{context} must declare {key} as #rrggbb, got {value!r}")


def flavor_color_block(flavor: dict, context: str) -> dict:
    block = flavor.get("dark") or flavor.get("light")
    if not isinstance(block, dict):
        fail(f"{context} must declare a dark or light color block")
    return block


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: dms_theme.py <theme.json>")

    theme_path = Path(sys.argv[1])
    theme = json.loads(theme_path.read_text())

    if theme.get("id") != "catppuccin":
        fail(f"vendored theme id must be catppuccin, got {theme.get('id')!r}")
    variants = theme.get("variants")
    if not isinstance(variants, dict) or variants.get("type") != "multi":
        fail("vendored theme must declare multi-variant support")

    defaults = variants.get("defaults")
    if not isinstance(defaults, dict) or not isinstance(defaults.get("dark"), dict):
        fail("vendored theme must declare per-mode variant defaults")

    flavors = variants.get("flavors")
    accents = variants.get("accents")
    if not isinstance(flavors, list) or not isinstance(accents, list):
        fail("vendored theme must declare flavors and accents lists")

    flavor_ids = {flavor.get("id") for flavor in flavors}
    if flavor_ids != EXPECTED_FLAVORS:
        fail(f"expected flavors {sorted(EXPECTED_FLAVORS)}, got {sorted(flavor_ids)}")

    failures: list[str] = []
    for flavor in flavors:
        flavor_id = flavor["id"]
        block = flavor_color_block(flavor, f"flavor {flavor_id!r}")
        require_hex_values(block, REQUIRED_FLAVOR_KEYS, f"flavor {flavor_id!r}")
        for text_key, fill_key in (("surfaceText", "surface"), ("backgroundText", "background")):
            ratio = contrast(block[text_key], block[fill_key])
            if ratio < MIN_TEXT_CONTRAST:
                failures.append(f"{flavor_id} {text_key}/{fill_key}: {ratio:.2f}:1 < {MIN_TEXT_CONTRAST}:1")

    accent_ids = {accent.get("id") for accent in accents}
    if SHIPPED_ACCENT not in accent_ids:
        fail(f"vendored theme must include the shipped {SHIPPED_ACCENT!r} accent, got {sorted(accent_ids)}")

    for accent in accents:
        accent_id = accent["id"]
        for flavor_id in sorted(EXPECTED_FLAVORS):
            block = accent.get(flavor_id)
            if not isinstance(block, dict):
                fail(f"accent {accent_id!r} must declare colors for flavor {flavor_id!r}")
            require_hex_values(block, REQUIRED_ACCENT_KEYS, f"accent {accent_id!r} flavor {flavor_id!r}")
            if accent_id == SHIPPED_ACCENT:
                ratio = contrast(block["primaryText"], block["primary"])
                if ratio < MIN_UI_CONTRAST:
                    failures.append(
                        f"{accent_id}.{flavor_id} primaryText/primary: {ratio:.2f}:1 < {MIN_UI_CONTRAST}:1"
                    )

    if failures:
        fail("DMS theme contrast failures:\n" + "\n".join(failures))


if __name__ == "__main__":
    main()
