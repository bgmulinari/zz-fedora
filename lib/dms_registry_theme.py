"""Install the default theme using the same backend request as Browse Themes."""
import json
import os
from pathlib import Path
import socket
import sys


def backend_socket():
    if os.environ.get("DMS_SOCKET"):
        return Path(os.environ["DMS_SOCKET"])
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    candidates = list(runtime.glob("danklinux-*.sock"))
    display = os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")
    if display:
        candidates = [path for path in candidates
                      if path.with_suffix(".session").is_file()
                      and path.with_suffix(".session").read_text().strip() == display]
    if len(candidates) != 1:
        raise RuntimeError("Could not identify the current session's DMS backend socket")
    return candidates[0]


def install_theme(socket_path, name):
    # DMSService.qml uses newline-delimited JSON with method/params/id.
    request = {"id": 1, "method": "themes.install", "params": {"name": name}}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(90)
        client.connect(str(socket_path))
        client.sendall((json.dumps(request) + "\n").encode())
        with client.makefile("r") as stream:
            for line in stream:
                response = json.loads(line)
                if response.get("id") != request["id"]:
                    continue
                if response.get("error"):
                    raise RuntimeError(str(response["error"]))
                return
    raise RuntimeError("DMS disconnected before confirming theme installation")


def clear_leftover_theme_dir(theme_dir):
    """Remove a theme directory that lost its theme.json.

    The backend refuses to install over an existing theme directory, even one
    without a theme.json, so a leftover (a broken theme.json link, preview
    images) would fail every retry. Anything else in it is the user's, so the
    directory is left alone and named in the error.
    """
    if not theme_dir.is_dir() or theme_dir.is_symlink():
        return
    entries = list(theme_dir.iterdir())
    unknown = [entry.name for entry in entries
               if not (entry.name == "theme.json" or entry.name.startswith("preview-"))
               or (entry.is_dir() and not entry.is_symlink())]
    if unknown:
        raise RuntimeError(f"{theme_dir} has no theme.json but holds {', '.join(sorted(unknown))}; "
                           "move it aside so DMS can install the theme")
    for entry in entries:
        entry.unlink()
    theme_dir.rmdir()


def install_default(home):
    config = home / ".config/DankMaterialShell"
    settings_file = config / "settings.json"
    if not settings_file.is_file():
        return
    settings = json.loads(settings_file.read_text())
    theme_file = config / "themes/catppuccin/theme.json"
    if (settings.get("currentThemeName") != "custom"
            or settings.get("customThemeFile") != str(theme_file)):
        return
    if theme_file.is_file():
        return
    clear_leftover_theme_dir(theme_file.parent)
    install_theme(backend_socket(), "catppuccin")
    if not theme_file.is_file() or json.loads(theme_file.read_text()).get("id") != "catppuccin":
        raise RuntimeError("DMS did not install a valid Catppuccin theme")
    print("installed")


if __name__ == "__main__":
    try:
        install_default(Path(sys.argv[1]))
    except (OSError, ValueError, RuntimeError) as error:
        print(f"DMS registry theme: {error}", file=sys.stderr)
        sys.exit(1)
