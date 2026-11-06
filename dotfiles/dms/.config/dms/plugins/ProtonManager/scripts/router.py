#!/usr/bin/python3
"""Stable Steam entrypoint; snapshot routing once per launch and exec real Proton."""
import json
import os
import re
from pathlib import Path
import sys


def available(path, runtime, root):
    if not isinstance(path, str) or not path:
        return False
    target = Path(path)
    if target.resolve() == root or not os.access(target / "proton", os.X_OK):
        return False
    try:
        # Steam may have updated an official build since it was selected. Do not
        # route a new runtime contract through metadata Steam cached previously.
        manifest = (target / "toolmanifest.vdf").read_text()
        match = re.search(r'"require_tool_appid"\s*"([0-9]+)"', manifest, re.IGNORECASE)
        return bool(match and match.group(1) == runtime)
    except OSError:
        return False


def main():
    root = Path(__file__).resolve().parent
    try:
        data = json.loads((root / "selection.json").read_text())
        override = ""
        for key in ("SteamGameId", "STEAM_COMPAT_APP_ID", "SteamAppId"):
            override = data["games"].get(os.environ.get(key, ""), "")
            if override:
                break
        selected = override or data["default"]
        if not available(selected, data["runtime"], root):
            raise RuntimeError("Selected Proton build is missing or incompatible: " + str(selected) + ". Open Proton Manager and choose an installed build.")
        target = Path(selected)
        # Keep Steam's runtime entry and expose the real Proton path to children.
        paths = os.environ.get("STEAM_COMPAT_TOOL_PATHS", "")
        tail = paths.partition(":")[2]
        os.environ["STEAM_COMPAT_TOOL_PATHS"] = str(target) + (":" + tail if tail else "")
        os.environ["STEAM_COMPAT_TOOL_PATH"] = str(target)
        os.environ["PROTON_MANAGER_TARGET"] = str(target)
        os.execv(str(target / "proton"), [str(target / "proton"), *sys.argv[1:]])
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RuntimeError) as error:
        print("Proton Manager: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
