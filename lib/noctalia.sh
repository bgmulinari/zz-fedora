#!/usr/bin/env bash
set -Eeuo pipefail

# Shared readers for the managed Noctalia configuration. The greeter
# appearance seed, the Noctalia state seeds, and first-run app theming all
# derive palette, mode, and wallpaper from this single source so they cannot
# drift from each other.

noctalia_managed_config_file() {
  printf '%s/dotfiles/noctalia/.config/noctalia/config.toml\n' "$ROOT_DIR"
}

noctalia_managed_palettes_dir() {
  printf '%s/palettes\n' "$(dirname "$(noctalia_managed_config_file)")"
}

# Print the quoted string value of a key inside one TOML section of the
# managed Noctalia config, or nothing when the section or key is absent.
# Lines are normalized (CRLF, surrounding whitespace) so cosmetic config
# edits cannot silently break the lookup.
noctalia_managed_config_value() {
  local section="[$1]" key="$2 = "
  awk -F'"' -v section="$section" -v key="$key" '
    { sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
    $0 == section { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && index($0, key) == 1 { print $2; exit }
  ' "$(noctalia_managed_config_file)"
}

# Resolved managed theme facts with the same fallbacks everywhere.
noctalia_managed_theme_mode() {
  local mode
  mode="$(noctalia_managed_config_value theme mode)"
  [[ -n "$mode" ]] || mode="dark"
  printf '%s\n' "$mode"
}

noctalia_managed_theme_source() {
  noctalia_managed_config_value theme source
}

noctalia_managed_custom_palette_name() {
  noctalia_managed_config_value theme custom_palette
}

noctalia_managed_default_wallpaper() {
  noctalia_managed_config_value wallpaper.default path
}
