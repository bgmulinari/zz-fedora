#!/usr/bin/python3
"""Configure the native theme integration for catalog browser selections.

Zen's documented DMS integration is userChrome.css (loaded at browser startup).
Run as the target user. Chromium-family theming is handled by machine policy.
"""

import argparse
import configparser
import io
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time


STYLE_PREF = "toolkit.legacyUserProfileCustomizations.stylesheets"


def write(path: Path, text: str) -> None:
    """Replace atomically, retaining an existing file as a timestamped backup."""
    if path.exists() and path.read_text() == text:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        shutil.copy2(path, path.with_name(f"{path.name}.bak.{time.time_ns()}"))
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def zen(home: Path, check: bool) -> bool:
    # These are Zen's native profile registry locations, not profile-name globs.
    registries = [p for p in (home / ".config/zen/profiles.ini", home / ".zen/profiles.ini")
                  if p.exists()]
    if not registries:
        registries = [home / ".config/zen/profiles.ini"]
    valid = True
    for registry in registries:
        config = configparser.ConfigParser(interpolation=None)
        config.optionxform = str
        if registry.exists():
            config.read(registry)
        profiles = [s for s in config.sections() if s.startswith("Profile")]
        created = not profiles
        if not profiles:
            if check:
                return False
            config["General"] = {"StartWithLastProfile": "1", "Version": "2"}
            config["Profile0"] = {
                "Name": "Default", "IsRelative": "1", "Path": "zz.default", "Default": "1",
            }
            profiles = ["Profile0"]
            # Mozilla's dedicated-profile selection only adopts a preseeded
            # default with a platform marker. This is the catalog RPM's runtime
            # directory, not a fabricated browser version or install hash.
            write(registry.parent / "zz.default/compatibility.ini",
                  "[Compatibility]\nLastPlatformDir=/opt/zen\n")
        for section in profiles:
            entry = config[section]
            profile = Path(entry["Path"])
            if entry.get("IsRelative", "1") == "1":
                profile = registry.parent / profile
            elif not profile.is_absolute():
                raise ValueError(f"Invalid absolute profile path in {registry}")
            user_js = profile / "user.js"
            prefs = user_js.read_text() if user_js.exists() else ""
            pattern = rf'^\s*user_pref\("{re.escape(STYLE_PREF)}",\s*(true|false)\s*\);[^\n]*$'
            values = re.findall(pattern, prefs, re.MULTILINE)
            css = profile / "chrome/userChrome.css"
            target = home / ".config/DankMaterialShell/zen.css"
            declaration = f"@import url({json.dumps(target.as_uri())});"
            linked = css.is_symlink() and css.resolve() == target.resolve()
            content = css.read_text() if css.exists() else ""
            if check:
                valid &= bool(values and values[-1] == "true") and (linked or declaration in content)
                continue
            if not values or values[-1] != "true":
                write(user_js, prefs.rstrip() + f'\nuser_pref("{STYLE_PREF}", true);\n')
            if not linked and declaration not in content:
                # Imports must precede other CSS rules. Leave personal overrides last.
                write(css, declaration + "\n" + content)
        if created:
            stream = io.StringIO()
            config.write(stream, space_around_delimiters=False)
            write(registry, stream.getvalue())
    if not check:
        print("Zen theme configured. Restart Zen to load DMS colors; later CSS palette changes also require a restart.")
    return bool(valid)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("browser", choices=["zen"])
    args = parser.parse_args()
    try:
        home = args.home.resolve()
        valid = zen(home, args.check)
        return 0 if valid else 1
    except (OSError, ValueError, KeyError, TypeError, configparser.Error) as error:
        print(f"Browser theme setup failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
