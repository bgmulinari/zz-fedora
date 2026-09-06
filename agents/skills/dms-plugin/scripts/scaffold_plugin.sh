#!/usr/bin/env bash
# Scaffold a ZZ-shipped DMS plugin from the upstream templates of the synced
# DMS reference checkout, then print the repository wiring to add next.
#
# Usage:
#   scaffold_plugin.sh --type widget|daemon|launcher|desktop --id camelId --name "Human Name"
#                      [--description "..."] [--author "..."] [--dir PascalName]
#                      [--root <repository>] [--dest <directory>] [--trigger "#"]
#
# The plugin lands in <root>/dotfiles/dms/.config/DankMaterialShell/plugins/<dir>/
# unless --dest names another directory (for a standalone dev copy, pass
# --dest ~/.config/DankMaterialShell/plugins/<dir>). Existing directories are
# never overwritten.
set -Eeuo pipefail

REF_ROOT="${ZZ_REF_ROOT:-/files/dev/ref-repos}"
DMS_DIR="$REF_ROOT/AvengeMedia/DankMaterialShell"
TEMPLATES="$DMS_DIR/.agents/skills/dms-plugin-dev/assets/templates"

type=""
id=""
name=""
description=""
author="ZZ"
dir=""
root="${ZZ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
dest=""
trigger=""

usage() { sed -n '2,13p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) type="$2"; shift 2 ;;
    --id) id="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --description) description="$2"; shift 2 ;;
    --author) author="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    --root) root="$2"; shift 2 ;;
    --dest) dest="$2"; shift 2 ;;
    --trigger) trigger="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$type" in
  widget|daemon|launcher|desktop) ;;
  composite)
    printf 'composite has no upstream template: scaffold each surface type into the same --dir, then merge the manifests into a "components" map (see the upstream SKILL.md).\n' >&2
    exit 2 ;;
  *) printf -- '--type must be widget, daemon, launcher, or desktop\n' >&2; exit 2 ;;
esac
[[ "$id" =~ ^[a-zA-Z][a-zA-Z0-9]*$ ]] ||
  { printf -- '--id must be camelCase matching ^[a-zA-Z][a-zA-Z0-9]*$ (got %q)\n' "$id" >&2; exit 2; }
[[ -n "$name" ]] || { printf -- '--name is required\n' >&2; exit 2; }
[[ -d "$TEMPLATES/$type" ]] ||
  { printf 'upstream templates not found under %s; run scripts/sync_refs.sh first\n' "$TEMPLATES" >&2; exit 1; }

if [[ -z "$dir" ]]; then
  dir="$(printf '%s' "${id:0:1}" | tr '[:lower:]' '[:upper:]')${id:1}"
fi
[[ -n "$description" ]] || description="$name plugin for the ZZ desktop"
kebab="$(printf '%s' "$id" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')"

if [[ -z "$dest" ]]; then
  dest="$root/dotfiles/dms/.config/DankMaterialShell/plugins/$dir"
fi

# Next free [choice] order in the desktop category: rows sort by order, and
# the catalog rejects nothing here, but a collision reorders the wizard.
next_order=90
if compgen -G "$root/catalog/units/desktop/*.toml" >/dev/null; then
  max_order="$(sed -n 's/^order *= *\([0-9]\+\).*/\1/p' "$root"/catalog/units/desktop/*.toml | sort -n | tail -n1)"
  [[ -n "$max_order" ]] && next_order=$((max_order + 10))
fi
[[ ! -e "$dest" ]] || { printf 'refusing to overwrite existing %s\n' "$dest" >&2; exit 1; }

# Template placeholders per type (from the upstream plugin.json files).
case "$type" in
  widget) tpl_id="myWidget"; tpl_name="My Widget" ;;
  daemon) tpl_id="myDaemon"; tpl_name="My Daemon" ;;
  launcher) tpl_id="myLauncher"; tpl_name="My Launcher" ;;
  desktop) tpl_id="myDesktopWidget"; tpl_name="My Desktop Widget" ;;
esac

mkdir -p "$dest"
cp -R "$TEMPLATES/$type/." "$dest/"

# Rename the template identity in every text file.
while IFS= read -r -d '' file; do
  sed -i \
    -e "s/\"$tpl_id\"/\"$id\"/g" \
    -e "s/$tpl_id\././g; s/\b$tpl_id\b/$id/g" \
    -e "s/$tpl_name/$name/g" \
    "$file"
done < <(find "$dest" -type f \( -name '*.qml' -o -name '*.json' -o -name '*.js' -o -name '*.md' \) -print0)

# Manifest fields the templates leave generic.
manifest="$dest/plugin.json"
tmp="$(mktemp)"
jq --arg d "$description" --arg a "$author" --arg t "$trigger" '
  .description = $d
  | .author = $a
  | (if $t != "" then .trigger = $t else . end)
' "$manifest" >"$tmp" && mv "$tmp" "$manifest"

if [[ -n "$trigger" ]]; then
  sed -i "s/property string trigger: \"#\"/property string trigger: \"$trigger\"/; s/\"trigger\", \"#\"/\"trigger\", \"$trigger\"/" "$dest"/*.qml
fi

cat <<EOF
Scaffolded $type plugin '$id' at:
  $dest

Files:
$(find "$dest" -type f | sed 's/^/  /')

Next, wire it into ZZ (see references/zz-wiring.md):

1. config/managed-config.tsv (tab-separated):
dms-plugin-$kebab	~/.config/DankMaterialShell/plugins/$dir	product-link	backup-before-link	dotfiles/dms/.config/DankMaterialShell/plugins/$dir	dms	Links the managed $name plugin.

2. catalog/units/desktop/$kebab.toml:
id = "desktop-$kebab"
description = "$description"
config = ["dms-plugin-$kebab"]

[choice]
category = "desktop"
id = "$kebab"
label = "$name"
default = true
order = $next_order
description = "$description"

# List the plugin's real system dependencies; "dms" is the payload when it has none.
[[install]]
backend = "dnf"
sources = ["copr:avengemedia/dms"]
packages = ["dms"]

3. Adding a desktop choice also touches tests that enumerate choices:
   tests/anaconda_addon.bats (ordered desktop choice list) and tests/dms_plugins.bats.
   default = true is required: tests/manifest_catalog.bats expects every
   non-browser choice to be a default.

4. Validate:
/usr/bin/python3 $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate_plugin.py "$dest"
/usr/bin/python3 "$root/lib/catalog.py" --root "$root" validate
EOF
