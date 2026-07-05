#!/usr/bin/env python3
"""Validate the managed Starship prompt against Noctalia built-in palettes."""

from __future__ import annotations

import csv
import re
import sys
import tomllib
from pathlib import Path


MIN_CONTRAST = 4.0
MIN_ADJACENT_CONTRAST = 1.1
MIN_ADJACENT_DISTANCE = 0.25
REPRESENTATIVE_PALETTE = "Catppuccin"
EXPECTED_BACKGROUND_TOKENS = ["text", "blue", "yellow", "blue", "green"]
EXPECTED_PALETTES = {
    "Ayu",
    "Catppuccin",
    "Dracula",
    "Eldritch",
    "Gruvbox",
    "Kanagawa",
    "Noctalia",
    "Nord",
    "Rosé Pine",
    "Tokyo-Night",
}

SECTION_GROUPS = [
    ("identity", [("os", "style"), ("username", "style_user"), ("username", "style_root")]),
    ("directory", [("directory", "style")]),
    ("git", [("git_branch", "format"), ("git_status", "format")]),
    (
        "language",
        [
            ("c", "format"),
            ("rust", "format"),
            ("golang", "format"),
            ("nodejs", "format"),
            ("php", "format"),
            ("java", "format"),
            ("kotlin", "format"),
            ("haskell", "format"),
            ("python", "format"),
            ("dotnet", "format"),
        ],
    ),
    ("time", [("time", "format")]),
]


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def parse_style(style: str) -> tuple[str, str]:
    fg = re.search(r"(?<![A-Za-z0-9_-])fg:([#A-Za-z0-9_-]+)", style)
    bg = re.search(r"(?<![A-Za-z0-9_-])bg:([#A-Za-z0-9_-]+)", style)
    if not fg or not bg:
        fail(f"could not find fg/bg style tokens in: {style}")
    return fg.group(1), bg.group(1)


def load_group_styles(config: dict) -> list[tuple[str, str, str]]:
    groups = []
    for group_name, refs in SECTION_GROUPS:
        pairs = []
        for table_name, key in refs:
            table = config.get(table_name)
            if not isinstance(table, dict):
                fail(f"missing Starship table [{table_name}]")
            value = table.get(key)
            if not isinstance(value, str):
                fail(f"missing Starship value [{table_name}].{key}")
            pairs.append(parse_style(value))

        unique_pairs = set(pairs)
        if len(unique_pairs) != 1:
            fail(f"{group_name} styles are inconsistent: {pairs}")

        fg, bg = pairs[0]
        groups.append((group_name, fg, bg))

    foregrounds = {fg for _, fg, _ in groups}
    if foregrounds != {"surface0"}:
        fail(f"Starship section text must consistently use fg:surface0, got: {sorted(foregrounds)}")

    backgrounds = [bg for _, _, bg in groups]
    if backgrounds != EXPECTED_BACKGROUND_TOKENS:
        fail(f"Starship section backgrounds must follow Noctalia tokens {EXPECTED_BACKGROUND_TOKENS}, got: {backgrounds}")
    for left, right in zip(groups, groups[1:]):
        if left[2] == right[2]:
            fail(f"adjacent Starship section backgrounds must be distinct, got {left[0]}->{right[0]} both using {left[2]}")

    return groups


def load_managed_theme(config_path: Path) -> tuple[str, str]:
    config = tomllib.loads(config_path.read_text())
    theme = config.get("theme", {})
    if theme.get("source") != "builtin":
        fail("managed Noctalia config must use the builtin palette source for this regression")
    mode = theme.get("mode")
    if mode != "dark":
        fail(f"fixture covers the managed dark prompt only, got theme.mode={mode!r}")
    builtin = theme.get("builtin")
    if not isinstance(builtin, str) or not builtin:
        fail(f"managed Noctalia config must declare theme.builtin, got {builtin!r}")
    return mode, builtin


def load_fixture(fixture_path: Path, mode: str) -> list[dict[str, str]]:
    with fixture_path.open(newline="") as handle:
        rows = [row for row in csv.DictReader(handle, delimiter="\t") if row["mode"] == mode]

    palettes = {row["palette"] for row in rows}
    if palettes != EXPECTED_PALETTES:
        fail(f"fixture palette set mismatch: expected {sorted(EXPECTED_PALETTES)}, got {sorted(palettes)}")

    return rows


def resolve_starship_palette(row: dict[str, str]) -> dict[str, str]:
    return {
        "blue": row["blue"],
        "red": row["red"],
        "green": row["green"],
        "yellow": row["yellow"],
        "cyan": row["cyan"],
        "magenta": row["magenta"],
        "white": row["white"],
        "black": row["black"],
        "rosewater": row["bright_yellow"],
        "flamingo": row["bright_red"],
        "pink": row["bright_magenta"],
        "mauve": row["magenta"],
        "maroon": row["bright_red"],
        "peach": row["bright_yellow"],
        "teal": row["cyan"],
        "sky": row["bright_cyan"],
        "sapphire": row["bright_blue"],
        "lavender": row["bright_magenta"],
        "text": row["foreground"],
        "subtext1": row["white"],
        "subtext0": row["bright_black"],
        "overlay2": row["bright_black"],
        "overlay1": row["bright_black"],
        "overlay0": row["black"],
        "surface2": row["black"],
        "surface1": row["black"],
        "surface0": row["background"],
        "base": row["background"],
        "mantle": row["background"],
        "crust": row["background"],
    }


def rgb(hex_color: str) -> tuple[float, float, float]:
    hex_color = hex_color.strip().lstrip("#")
    return tuple(int(hex_color[index : index + 2], 16) / 255 for index in (0, 2, 4))


def linear_channel(value: float) -> float:
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def luminance(hex_color: str) -> float:
    red, green, blue = rgb(hex_color)
    return 0.2126 * linear_channel(red) + 0.7152 * linear_channel(green) + 0.0722 * linear_channel(blue)


def contrast(first: str, second: str) -> float:
    first_luminance = luminance(first)
    second_luminance = luminance(second)
    lighter = max(first_luminance, second_luminance)
    darker = min(first_luminance, second_luminance)
    return (lighter + 0.05) / (darker + 0.05)


def color_distance(first: str, second: str) -> float:
    first_rgb = rgb(first)
    second_rgb = rgb(second)
    return sum((first_channel - second_channel) ** 2 for first_channel, second_channel in zip(first_rgb, second_rgb)) ** 0.5


def resolve_color(palette: dict[str, str], token: str) -> str:
    if token.startswith("#"):
        return token
    try:
        return palette[token]
    except KeyError:
        fail(f"unknown Starship color token: {token}")


def validate_separators(config: dict, groups: list[tuple[str, str, str]]) -> None:
    prompt_format = config.get("format")
    if not isinstance(prompt_format, str):
        fail("missing Starship format string")

    backgrounds = {group_name: background for group_name, _, background in groups}

    start = re.search(r"\[\]\(([^)]+)\)", prompt_format)
    if not start or start.group(1) != backgrounds["identity"]:
        fail(f"left prompt cap must use {backgrounds['identity']}, got {start.group(1) if start else 'missing'}")

    transitions = [parse_style(style) for style in re.findall(r"\[\]\(([^)]+)\)", prompt_format)]
    expected_transitions = [(backgrounds["identity"], backgrounds["directory"])]
    if transitions != expected_transitions:
        fail(f"top-level prompt separators must only cover required sections: expected {expected_transitions}, got {transitions}")

    custom = config.get("custom")
    if not isinstance(custom, dict):
        fail("missing Starship [custom] separator tables")

    expected_custom_separators = {
        "git_start": (backgrounds["directory"], backgrounds["git"]),
        "language_start": (backgrounds["git"], backgrounds["language"]),
        "time_start_after_git": (backgrounds["git"], backgrounds["time"]),
        "time_start_after_blue": (backgrounds["language"], backgrounds["time"]),
    }
    for separator_name, expected_pair in expected_custom_separators.items():
        table = custom.get(separator_name)
        if not isinstance(table, dict):
            fail(f"missing Starship custom separator [custom.{separator_name}]")
        separator_format = table.get("format")
        if not isinstance(separator_format, str):
            fail(f"missing Starship custom separator format for [custom.{separator_name}]")
        match = re.fullmatch(r"\[\]\(([^)]+)\)", separator_format)
        if not match:
            fail(f"[custom.{separator_name}] must render exactly one separator glyph, got: {separator_format}")
        pair = parse_style(match.group(1))
        if pair != expected_pair:
            fail(f"[custom.{separator_name}] must use separator colors {expected_pair}, got {pair}")
        if not table.get("when"):
            fail(f"[custom.{separator_name}] must be conditional")

    end = re.search(r"\[ \]\(fg:([^)]+)\)", prompt_format)
    if not end or end.group(1) != backgrounds["time"]:
        fail(f"right prompt cap must use {backgrounds['time']}, got {end.group(1) if end else 'missing'}")


def validate_contrast(rows: list[dict[str, str]], groups: list[tuple[str, str, str]], palette_names: set[str]) -> None:
    failures = []
    for row in rows:
        if row["palette"] not in palette_names:
            continue
        palette = resolve_starship_palette(row)
        terminal_background = resolve_color(palette, "surface0")
        resolved_backgrounds = []
        for group_name, foreground, background in groups:
            foreground_hex = resolve_color(palette, foreground)
            background_hex = resolve_color(palette, background)
            resolved_backgrounds.append((group_name, background, background_hex))
            text_ratio = contrast(foreground_hex, background_hex)
            terminal_ratio = contrast(background_hex, terminal_background)
            if text_ratio < MIN_CONTRAST or terminal_ratio < MIN_CONTRAST:
                failures.append(
                    f"{row['palette']} {row['mode']} {group_name}: "
                    f"text={text_ratio:.2f}:1 terminal={terminal_ratio:.2f}:1 "
                    f"fg {foreground}={foreground_hex} bg {background}={background_hex} terminal={terminal_background}"
                )

        for left, right in zip(resolved_backgrounds, resolved_backgrounds[1:]):
            adjacent_ratio = contrast(left[2], right[2])
            adjacent_distance = color_distance(left[2], right[2])
            if adjacent_ratio < MIN_ADJACENT_CONTRAST and adjacent_distance < MIN_ADJACENT_DISTANCE:
                failures.append(
                    f"{row['palette']} {row['mode']} {left[0]}->{right[0]} boundary: "
                    f"adjacent={adjacent_ratio:.2f}:1 distance={adjacent_distance:.2f} "
                    f"{left[1]}={left[2]} {right[1]}={right[2]}"
                )

    if failures:
        fail("Starship prompt contrast failures:\n" + "\n".join(failures))


def main() -> None:
    if len(sys.argv) != 4:
        fail("usage: starship_contrast.py <starship.toml> <palette-fixture.tsv> <noctalia-config.toml>")

    starship_path = Path(sys.argv[1])
    fixture_path = Path(sys.argv[2])
    noctalia_config_path = Path(sys.argv[3])

    mode, managed_palette = load_managed_theme(noctalia_config_path)
    starship_config = tomllib.loads(starship_path.read_text())
    groups = load_group_styles(starship_config)
    validate_separators(starship_config, groups)
    rows = load_fixture(fixture_path, mode)
    validate_contrast(rows, groups, {managed_palette, REPRESENTATIVE_PALETTE})


if __name__ == "__main__":
    main()
