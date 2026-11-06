#!/usr/bin/python3
"""Launcher inventories, transactional Steam selection and runtime installations.

The line-delimited JSON protocol keeps filesystem/network work out of the shell UI.
Release metadata is cached locally; runtime changes require explicit actions. No Steam configuration files are rewritten.
"""
from __future__ import annotations

import argparse
import providers
import targets
import release_cache
import github_cli
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

SLOT = "Proton-Manager"
OWNER = "proton-manager-v1"
MAX_DOWNLOAD = 2 * 1024**3
MAX_EXPANDED = 8 * 1024**3


class ManagerError(Exception):
    pass


def emit(kind, **values):
    print(json.dumps({"type": kind, **values}), flush=True)


def read_text(path):
    try:
        return Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def vdf(text):
    """Parse Valve's quoted/bare KeyValues, preserving nested scopes."""
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|//[^\n]*|[{}]|[^\s{}"]+', text)
    tokens = [t for t in tokens if not t.startswith("//")]
    index = 0

    def string(token):
        if token.startswith('"'):
            return re.sub(r'\\([\\"])', r'\1', token[1:-1])
        return token

    def block(nested=False):
        nonlocal index
        result = {}
        while index < len(tokens):
            key = tokens[index]
            index += 1
            if key == "}":
                if not nested:
                    raise ManagerError("Unexpected closing brace in Steam metadata")
                return result
            if key == "{" or index == len(tokens):
                raise ManagerError("Incomplete Steam metadata")
            value = tokens[index]
            index += 1
            if value == "}":
                raise ManagerError("Missing Steam metadata value")
            result[string(key).lower()] = block(True) if value == "{" else string(value)
        if nested:
            raise ManagerError("Unclosed Steam metadata block")
        return result

    return block()


def atomic_json(path, value):
    path = Path(path)
    fd, name = tempfile.mkstemp(prefix=".selection-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def unique_dirs(paths):
    return list(dict.fromkeys(p.resolve() for p in paths if p.is_dir()))


def steam_roots(home=None):
    home = home or Path.home()
    data = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
    return unique_dirs([home / ".steam/root", home / ".steam/steam", data / "Steam",
                        home / ".steam/debian-installation", home / "snap/steam/common/.steam/root",
                        home / ".var/app/com.valvesoftware.Steam/data/Steam",
                        home / ".var/app/com.valvesoftware.Steam/.steam/root"])


def libraries(root):
    paths = [root]
    for file in (root / "steamapps/libraryfolders.vdf", root / "config/libraryfolders.vdf"):
        entries = vdf(read_text(file)).get("libraryfolders", {})
        if not isinstance(entries, dict):
            continue
        for key, entry in entries.items():
            path = entry.get("path") if isinstance(entry, dict) else entry if key.isdigit() else None
            if path:
                paths.append(Path(path))
    return unique_dirs(paths)


def build_timestamp(path):
    version = read_text(path / "version").split()
    if version and version[0].isdigit() and 946684800 <= int(version[0]) <= 4102444800:
        return int(version[0])
    return path.stat().st_mtime


def managed_build(path):
    if path.is_symlink():
        return False
    try:
        marker = json.loads(read_text(path / ".proton-manager-install.json") or "{}")
        return isinstance(marker, dict) and marker.get("owner") == OWNER
    except (OSError, ValueError):
        return False


def tool_info(path, official=False, name=""):
    managed = managed_build(path)
    path = path.resolve()
    if not os.access(path / "proton", os.X_OK) or path.name == SLOT:
        return None
    manifest = vdf(read_text(path / "toolmanifest.vdf")).get("manifest", {})
    runtime = manifest.get("require_tool_appid", "")
    # Tools without an explicit runtime contract remain visible, but cannot be routed.
    compat = vdf(read_text(path / "compatibilitytool.vdf")).get("compatibilitytools", {}).get("compat_tools", {})
    names = [item.get("display_name", "") for item in compat.values() if isinstance(item, dict)]
    return {"path": str(path), "name": name or next((n for n in names if n), path.name),
            "buildTime": build_timestamp(path), "runtime": runtime, "official": official, "managed": managed}


def read_selection(root):
    slot = root / "compatibilitytools.d" / SLOT
    if not slot.exists():
        return None
    if slot.is_symlink() or read_text(slot / ".owner").strip() != OWNER:
        raise ManagerError(f"{slot} is not a Proton Manager-owned selector; it was left untouched")
    data = json.loads((slot / "selection.json").read_text())
    if (not isinstance(data, dict) or data.get("owner") != OWNER
            or not isinstance(data.get("runtime"), str) or not data["runtime"].isdigit()
            or not isinstance(data.get("default"), str) or not Path(data["default"]).is_absolute()
            or not isinstance(data.get("games"), dict)
            or any(not re.fullmatch(r"[0-9]{1,20}", key) or not isinstance(value, str)
                   or not Path(value).is_absolute() for key, value in data["games"].items())):
        raise ManagerError("Selector configuration is invalid")
    return {key: data[key] for key in ("owner", "runtime", "default", "games")}



def inventory(root):
    tools, games, warnings = {}, {}, []
    dirs = [root / "compatibilitytools.d"]
    # Flatpak Steam cannot necessarily access tools in the host's system directories.
    if "/.var/app/" not in str(root):
        dirs += [Path("/usr/share/steam/compatibilitytools.d"), Path("/usr/local/share/steam/compatibilitytools.d")]
        dirs += [Path(p) for p in os.environ.get("STEAM_EXTRA_COMPAT_TOOLS_PATHS", "").split(":") if p]
    for directory in unique_dirs(dirs):
        for child in sorted(directory.iterdir()):
            if child.name.startswith(".") or child.name == SLOT:
                continue
            try:
                candidates = [child] if child.is_dir() else []
                if child.suffix == ".vdf":
                    entries = vdf(read_text(child)).get("compatibilitytools", {}).get("compat_tools", {})
                    candidates += [directory / entry["install_path"] for entry in entries.values()
                                   if isinstance(entry, dict) and entry.get("install_path")]
                for path in candidates:
                    tool = tool_info(path)
                    if tool:
                        tools[tool["path"]] = tool
            except (OSError, ValueError, ManagerError) as error:
                warnings.append(f"{child.name}: {error}")
    for library in libraries(root):
        for file in sorted((library / "steamapps").glob("appmanifest_*.acf")):
            try:
                app = vdf(read_text(file)).get("appstate", {})
                appid, name, folder = app.get("appid", ""), app.get("name", ""), app.get("installdir", "")
                if not appid.isdigit() or not folder:
                    continue
                path = (library / "steamapps/common" / folder).resolve()
                if not path.is_relative_to((library / "steamapps/common").resolve()):
                    continue
                tool = tool_info(path, True, name)
                if tool:
                    tools[tool["path"]] = tool
                elif not name.startswith("Steam Linux Runtime"):
                    games[appid] = {"id": appid, "name": name, "library": str(library)}
            except (OSError, ValueError, ManagerError) as error:
                warnings.append(f"{file.name}: {error}")
    selection = None
    try:
        selection = read_selection(root)
    except (OSError, ValueError, ManagerError) as error:
        warnings.append(f"Selector at {root}: {error}")
    if selection:
        chosen = [("Active build", selection["default"])] + [("Build for game " + appid, path) for appid, path in selection["games"].items()]
        for label, path in chosen:
            tool = tools.get(path)
            if not tool or tool["runtime"] != selection["runtime"]:
                warnings.append(label + " is missing or incompatible. Choose another installed build.")
        for appid in selection["games"]:
            games.setdefault(appid, {"id": appid, "name": f"Game {appid}", "library": "Manual override"})
    return {"tools": sorted(tools.values(), key=lambda t: t["name"].casefold()),
            "games": sorted(games.values(), key=lambda g: g["name"].casefold()),
            "selection": selection, "warnings": warnings}


@contextlib.contextmanager
def locked(root, target=None):
    directory = Path(target["directory"]) if target else root / "compatibilitytools.d"
    if target and target["launcher"] == "heroic":
        directory = directory.parent
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / ".proton-manager.lock").open("a") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ManagerError("Another Proton operation is running. Try again when it finishes.") from error
        yield


def validated_tool(root, path):
    tool = next((t for t in inventory(root)["tools"] if t["path"] == path), None)
    if not tool:
        raise ManagerError("That Proton build is no longer installed. Refresh the list.")
    if not tool["runtime"].isdigit():
        raise ManagerError("This build has no supported Steam runtime manifest. Select it directly in Steam.")
    return tool


def select(root, path, scope="default", game=""):
    if scope not in ("default", "game"):
        raise ManagerError("Unknown selection scope")
    if scope == "game" and not re.fullmatch(r"[0-9]{1,20}", game):
        raise ManagerError("Enter a numeric Steam App ID (up to 20 digits)")
    selection = read_selection(root)
    tool = validated_tool(root, path) if path else None
    if not selection and (scope != "default" or not tool):
        raise ManagerError("Choose a default Proton build first")
    if tool and selection and tool["runtime"] != selection["runtime"]:
        raise ManagerError("This build needs a different Steam Linux Runtime. Select it directly in Steam; live switching is limited to the registered runtime.")
    first = selection is None
    if first:
        selection = {"owner": OWNER, "runtime": tool["runtime"], "default": path, "games": {}}
        directory = root / "compatibilitytools.d"
        with tempfile.TemporaryDirectory(prefix=".proton-manager-register-", dir=directory) as stage:
            staged = Path(stage) / SLOT
            staged.mkdir()
            (staged / ".owner").write_text(OWNER + "\n")
            (staged / "compatibilitytool.vdf").write_text(
                '"compatibilitytools" { "compat_tools" { "proton_manager" { '
                '"install_path" "." "display_name" "Proton Manager" '
                '"from_oslist" "windows" "to_oslist" "linux" } } }\n')
            shutil.copyfile(Path(path) / "toolmanifest.vdf", staged / "toolmanifest.vdf")
            shutil.copyfile(Path(__file__).with_name("router.py"), staged / "proton")
            (staged / "proton").chmod(0o755)
            atomic_json(staged / "selection.json", selection)
            staged.rename(directory / SLOT)
    else:
        selection = {**selection, "games": dict(selection["games"])}
        if scope == "game":
            if path:
                selection["games"][game] = path
            else:
                selection["games"].pop(game, None)
        else:
            if scope == "default" and not path:
                raise ManagerError("The default build cannot be empty")
            selection[scope] = path
        atomic_json(root / "compatibilitytools.d" / SLOT / "selection.json", selection)
    return "Restart Steam once, then choose Proton Manager in the game's Compatibility settings." if first else "Saved. Applies on the next game launch; Steam can stay open."


def request(url, headers=None):
    api = any(url == p["api"] or url.startswith(p["api"] + "/") or url.startswith(p["api"] + "?") for p in providers.PROVIDERS.values())
    asset = any(url.startswith(p["origin"] + "releases/download/") or url.startswith(p["origin"] + "attachments/") for p in providers.PROVIDERS.values())
    # Forgejo attachment downloads use a host-scoped attachment UUID.
    asset = asset or url.startswith("https://dawn.wine/attachments/")
    if not (api or asset):
        raise ManagerError("Unexpected release download URL")
    accept = "application/vnd.github.full+json" if api else "application/octet-stream"
    req = urllib.request.Request(url, headers={"User-Agent": "Proton-Manager/1.0", "Accept": accept, **(headers or {})})
    return urllib.request.urlopen(req, timeout=30)


FETCH_STATUS = {}


def fetch_json(url):
    global FETCH_STATUS
    try:
        data, FETCH_STATUS = release_cache.fetch(url, request, lambda: github_cli.request if github_cli.authenticated() else None)
    except github_cli.Unavailable:
        data, FETCH_STATUS = release_cache.fetch(url, request)
    return data


def releases(provider="ge", page=1):
    global FETCH_STATUS
    FETCH_STATUS = {}
    source = providers.PROVIDERS[provider]
    query = "per_page=30" if "api.github.com" in source["api"] else "limit=30"
    data = fetch_json(source["api"] + "?" + query + "&page=" + str(page))
    if not isinstance(data, list):
        raise ManagerError("The release source returned an invalid catalog")
    return {"releases": [item for release in data for item in providers.assets(release, provider)],
            "page": page, "hasMore": len(data) == 30 and page < 100, **FETCH_STATUS}


def unpack(archive, destination, kind="proton"):
    if not hasattr(tarfile, "data_filter"):
        raise ManagerError("Python's safe tar extraction support is required")
    with tarfile.open(archive, "r:*") as tar:
        members = tar.getmembers()
        if len(members) > 250000 or sum(m.size for m in members) > MAX_EXPANDED:
            raise ManagerError("Archive exceeds the extraction limit")
        for member in members:
            if member.name.startswith("/") or ".." in Path(member.name).parts:
                raise ManagerError("Unsafe path in release archive")
        tar.extractall(destination, members=members, filter="data")
    entries = list(destination.iterdir())
    if len(entries) != 1 or not entries[0].is_dir() or entries[0].is_symlink():
        raise ManagerError("Release must contain exactly one build directory")
    if kind == "proton" and not tool_info(entries[0]):
        raise ManagerError("Release does not contain an executable Proton build")
    if kind == "wine" and not any(os.access(entries[0] / "bin" / exe, os.X_OK) for exe in ("wine", "wine64")):
        raise ManagerError("Release does not contain an executable Wine build")
    if kind in ("dxvk", "vkd3d") and not any(entries[0].glob("**/*.dll")):
        raise ManagerError("Release does not contain graphics components")
    return entries[0]


def install(root, tag, provider="ge", asset="", target=None):
    if not tag or len(tag) > 200 or any(ord(c) < 32 for c in tag):
        raise ManagerError("Invalid release tag")
    source = providers.PROVIDERS[provider]
    if target and not targets.supports(target, source["kind"]):
        raise ManagerError("This source does not support the selected launcher")
    candidates = providers.assets(fetch_json(source["api"] + "/tags/" + urllib.parse.quote(tag, safe="")), provider)
    info = next((item for item in candidates if item["asset"] == asset), None) if asset else next(iter(candidates), None)
    if not info:
        raise ManagerError("No matching release asset is available for this architecture")
    directory = targets.directory(target, source["kind"]) if target else root / "compatibilitytools.d"
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / info["name"]
    if destination.exists() or destination.is_symlink():
        raise ManagerError("This build is already installed")
    if not 0 < info["size"] <= MAX_DOWNLOAD:
        raise ManagerError("Release size is outside the supported limit")
    if shutil.disk_usage(directory).free < info["size"] + MAX_EXPANDED:
        raise ManagerError("At least 8 GiB plus the download size must be free for staging")
    algorithm, expected = info["algorithm"], ""
    if info["checksum"]:
        with request(info["checksum"]) as response:
            checksum_text = response.read(65536).decode("utf-8")
        lines = [line.split() for line in checksum_text.splitlines() if line.strip()]
        matching = [line[0] for line in lines if len(line) > 1 and line[-1].lstrip("*") == info["asset"]]
        expected = matching[0] if matching else lines[0][0] if len(lines) == 1 and len(lines[0]) == 1 else ""
    elif info["digest"]:
        algorithm, expected = info["digest"].split(":", 1)
    if algorithm and not re.fullmatch(r"[a-fA-F0-9]{%d}" % (128 if algorithm == "sha512" else 64), expected):
        raise ManagerError("The release checksum is invalid")
    with tempfile.TemporaryDirectory(prefix=".proton-manager-download-", dir=directory) as temporary:
        stage = Path(temporary)
        archive = stage / "release.tar.gz"
        digest, downloaded, last = hashlib.new(algorithm or "sha256"), 0, 0
        with request(info["url"]) as response, archive.open("wb") as stream:
            while chunk := response.read(1024 * 1024):
                downloaded += len(chunk)
                if downloaded > info["size"]:
                    raise ManagerError("Download exceeds the advertised size")
                digest.update(chunk)
                stream.write(chunk)
                if time.monotonic() - last > 0.2:
                    emit("progress", message="Downloading " + info["name"], percent=round(downloaded / info["size"] * 100))
                    last = time.monotonic()
        if downloaded != info["size"] or (expected and digest.hexdigest().lower() != expected.lower()):
            raise ManagerError("Checksum or size mismatch; nothing was installed")
        emit("progress", message="Checksum verified. Extracting…" if expected else "Download complete. Extracting…", percent=100)
        extracted = stage / "unpacked"
        extracted.mkdir()
        build = unpack(archive, extracted, source["kind"])
        atomic_json(build / ".proton-manager-install.json", {"owner": OWNER, "tag": tag, "provider": provider, "kind": source["kind"], "asset": info["asset"], "digest": (algorithm or "sha256") + ":" + digest.hexdigest(), "verified": bool(expected)})
        build.rename(destination)
    return f"{info['name']} installed. " + ("Choose it in Installed builds." if not target or target["launcher"] == "steam" else "Select it in your launcher’s game settings.")


def steam_running():
    # Refuse removals for the whole Steam session: a just-launched game may not yet
    # expose its Proton path in /proc. Selection changes never remove build files.
    for process in Path("/proc").glob("[0-9]*"):
        try:
            if process.stat().st_uid == os.getuid() and (process / "comm").read_text().strip() in ("steam", "steam.exe", "steamwebhelper", "pressure-vessel", "wineserver"):
                return True
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return False


def remove(root, path, target=None):
    directory = Path(target["directory"]) if target else root / "compatibilitytools.d"
    build = Path(path)
    allowed = [directory.resolve()]
    if target and target["launcher"] in ("heroic", "lutris"):
        allowed += [targets.directory(target, kind).resolve() for kind in ("dxvk", "vkd3d")]
    if build.is_symlink() or build.parent.resolve() not in allowed or build.name == SLOT:
        raise ManagerError("Only builds installed here by Proton Manager can be removed")
    marker = json.loads(read_text(build / ".proton-manager-install.json") or "{}")
    if marker.get("owner") != OWNER:
        raise ManagerError("This build is managed outside Proton Manager; remove it with its original manager")
    for candidate in steam_roots() + ([root] if not target or target["launcher"] == "steam" else []):
        try:
            selection = read_selection(candidate)
        except (OSError, ValueError, ManagerError) as error:
            # A broken selector can only refer to tools visible in that Steam library.
            # Preserve those builds, but let unrelated launchers/libraries be managed.
            if any(tool["path"] == str(build.resolve()) for tool in inventory(candidate)["tools"]):
                raise ManagerError(f"Cannot verify whether this build is selected by {candidate}. Fix its selector configuration before removing it: {error}") from error
            continue
        if not selection:
            continue
        if str(build.resolve()) == selection.get("default"):
            raise ManagerError("This build is active. Set another build as active before removing it.")
        if str(build.resolve()) in selection["games"].values():
            raise ManagerError("This build is assigned to a game. Change that game’s build before removing it.")
    if steam_running():
        raise ManagerError("Close Steam and running games before removing a Proton build")
    if target and target["launcher"] != "steam":
        # Inspect launcher settings before deleting; never rewrite another app's settings.
        settings = Path(target["config"])
        for folder, dirs, files in os.walk(settings):
            dirs[:] = [name for name in dirs if name not in ("tools", "runners", "runtime", "drive_c", "dosdevices", "cache", "Cache", "logs", ".git")]
            for name in files:
                if not name.endswith((".json", ".yml", ".yaml")):
                    continue
                file = Path(folder) / name
                if file.is_file() and file.stat().st_size < 4 * 1024**2 and build.name in file.read_text(errors="replace"):
                    raise ManagerError("This build is referenced in launcher settings. Change the game’s runner first.")
        if launcher_running(target):
            raise ManagerError("Close the launcher and running games before removing a build")
    shutil.rmtree(build)
    return "Build removed."


def launcher_running(target):
    names = {"heroic": ("heroic",), "lutris": ("lutris",), "bottles": ("bottles",), "winezgui": ("winezgui",)}.get(target["launcher"], ())
    for process in Path("/proc").glob("[0-9]*"):
        try:
            if process.stat().st_uid != os.getuid():
                continue
            args = (process / "cmdline").read_bytes().decode(errors="replace").lower().split("\0")
            if any(Path(arg).name in names for arg in args[:3]):
                return True
        except (OSError, ValueError):
            pass
    return False


def target_inventory(target):
    if target["launcher"] == "steam":
        return inventory(Path(target["path"]))
    tools, warnings = [], []
    directories = [Path(target["directory"])]
    if target["launcher"] in ("heroic", "lutris"):
        directories += [targets.directory(target, kind) for kind in ("dxvk", "vkd3d")]
    for directory in directories:
        if not directory.is_dir():
            continue
        for child in sorted(directory.iterdir()):
            if child.name.startswith(".") or not child.is_dir():
                continue
            try:
                tool = tool_info(child)
                if not tool and (any(os.access(child / "bin" / exe, os.X_OK) for exe in ("wine", "wine64")) or directory.name in ("dxvk", "vkd3d")):
                    tool = dict(path=str(child.resolve()), name=child.name, buildTime=build_timestamp(child), runtime="", official=False,
                                managed=managed_build(child))
                if tool:
                    # Keep the lexical path so a symlink can never acquire removal authority.
                    tool["path"] = str(child)
                    tool["managed"] = tool["managed"] and not child.is_symlink()
                    tools.append(tool)
            except (OSError, ValueError, ManagerError) as error:
                warnings.append(f"{child.name}: {error}")
    return dict(tools=tools, games=[], selection=None, warnings=warnings)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["scan", "releases", "select", "install", "remove"])
    parser.add_argument("--root", default="")
    parser.add_argument("--tool", default="")
    parser.add_argument("--scope", default="default")
    parser.add_argument("--game", default="")
    parser.add_argument("--tag", default="")
    parser.add_argument("--provider", default="ge", choices=list(providers.PROVIDERS))
    parser.add_argument("--asset", default="")
    parser.add_argument("--page", default=1, type=int)
    args = parser.parse_args()
    try:
        destinations = targets.discover(steam_roots())
        path = str(Path(args.root).expanduser().resolve()) if args.root else ""
        target = next((t for t in destinations if t["path"] == path), None) if path else next(iter(destinations), None)
        if path and not target and args.action == "scan":
            target = next(iter(destinations), None)
        elif path and not target:
            raise ManagerError("Launcher installation is no longer available. Refresh the list.")
        root = Path(target["path"]) if target else None
        if args.action == "releases":
            if not 1 <= args.page <= 100:
                raise ManagerError("Invalid release page")
            if not targets.supports(target, providers.PROVIDERS[args.provider]["kind"]):
                raise ManagerError("This source does not support the selected launcher")
            emit("result", **releases(args.provider, args.page))
            return
        if args.action == "scan":
            sources = [dict(id=key, name=p["name"], description=p["description"]) for key, p in providers.PROVIDERS.items() if targets.supports(target, p["kind"])]
            emit("result", roots=destinations, target=target, providers=sources,
                 root=str(root) if root else "", **(target_inventory(target) if target else {"tools": [], "games": [], "selection": None, "warnings": []}))
            return
        if not target:
            raise ManagerError("Open a supported launcher once, then refresh")
        with locked(root, target):
            if args.action == "select" and target["launcher"] != "steam":
                raise ManagerError("Select this build in your launcher’s game settings")
            if args.action == "select":
                message = select(root, args.tool, args.scope, args.game)
            elif args.action == "install":
                message = install(root, args.tag, args.provider, args.asset, target)
            else:
                message = remove(root, args.tool, target)
        emit("result", message=message)
    except (release_cache.RateLimited, ManagerError, OSError, ValueError, KeyError, TypeError, AttributeError, tarfile.TarError, urllib.error.URLError) as error:
        emit("error", message=str(error), retryAt=getattr(error, "retry_at", 0))
        sys.exit(1)


if __name__ == "__main__":
    def cancel(_signal, _frame):
        raise SystemExit(130)
    signal.signal(signal.SIGTERM, cancel)
    main()
