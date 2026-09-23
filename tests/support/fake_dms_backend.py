"""Answer one themes.install request the way the DMS backend does.

Usage: fake_dms_backend.py <socket> <home>

Listens on <socket>, and on a themes.install request writes the theme into
<home>'s DMS themes directory before replying, then exits.
"""
import json
from pathlib import Path
import socket
import sys

socket_path, home = Path(sys.argv[1]), Path(sys.argv[2])
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
    server.bind(str(socket_path))
    server.listen(1)
    server.settimeout(30)
    connection, _ = server.accept()
    with connection, connection.makefile("rw") as stream:
        request = json.loads(stream.readline())
        name = request["params"]["name"]
        theme_dir = home / ".config/DankMaterialShell/themes" / name
        theme_dir.mkdir(parents=True)
        (theme_dir / "theme.json").write_text(json.dumps({"id": name}))
        stream.write(json.dumps({"id": request["id"], "result": {}}) + "\n")
        stream.flush()
