#!/usr/bin/python3
import importlib.machinery, importlib.util, io, json, pathlib, struct, sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).parent))
loader = importlib.machinery.SourceFileLoader("codex_pet", sys.argv[1])
spec = importlib.util.spec_from_loader("codex_pet", loader)
pet = importlib.util.module_from_spec(spec)
loader.exec_module(pet)

# An asar the way Electron writes one: sizes, the JSON index, then the files.
sheet = b"RIFF\0\0\0\0WEBPVP8Lnewest"
older = b"RIFF\0\0\0\0WEBPVP8Lolder"
index = json.dumps({"files": {"webview": {"files": {"assets": {"files": {
    "codex-spritesheet-v5.aaaa.webp": {"size": len(older), "offset": "0"},
    "codex-spritesheet-v6.bbbb.webp": {"size": len(sheet), "offset": str(len(older))},
    "dewey-spritesheet-v9.cccc.webp": {"size": len(older), "offset": "0"},
}}}}}}).encode()
pad = -(len(index) + 8) % 4
header = struct.pack("<IIII", 4, len(index) + 8 + pad, len(index) + 4 + pad, len(index)) + index + b"\0" * pad
archive = pathlib.Path(sys.argv[2])
archive.write_bytes(header + older + sheet)

cache = pet.cache_root()
found = pet.from_app(archive, cache)
print("app", found.name, found.read_bytes() == sheet)

# With no app, Codex's own copy stands, with nothing fetched.
pet.CHATGPT_ARCHIVE = pathlib.Path("/nonexistent/app.asar")
def no_network(*a, **k): raise AssertionError("fetched")
pet.urllib.request.urlopen = no_network
pet.main()

# A download that is not a WebP is refused rather than installed.
class Reply(io.BytesIO):
    def __enter__(self): return self
    def __exit__(self, *a): return False
target = cache / "fetched.webp"
pet.urllib.request.urlopen = lambda request, timeout=30: Reply(b"<html>nope</html>")
print("html", pet.fetch(target), target.exists())
pet.urllib.request.urlopen = lambda request, timeout=30: Reply(b"RIFF\0\0\0\0WEBPVP8Lx")
print("webp", pet.fetch(target), target.exists())
