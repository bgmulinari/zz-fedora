"""Parse the Dux Shell settings specs into plain Python data.

The specs are JavaScript object literals shipped with the shell
(`Common/settings/{SettingsSpec,SessionSpec}.js`, each merged from a shared
spec in the `DCommon` library). They are the only place DMS records a default
for every key, so promoting live settings into the ZZ seed needs them to tell a
deliberate change apart from an untouched default.

Values are the literal subset the specs use (objects, arrays, double-quoted
strings, numbers, booleans, and null) plus bare JavaScript expressions, such as
a `coerce: Util.percentToUnit` reference or a `def: lockWidgetDefaults()` call.
An expression is never evaluated: a key whose default holds one is reported by
`computed_keys` rather than given a value. Anything else raises, so a future
spec that outgrows this parser fails loudly instead of silently reporting wrong
defaults.
"""

from __future__ import annotations

import json
import pathlib
import re

_KEY = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")


class SpecError(RuntimeError):
    pass


class Opaque:
    """A bare JavaScript expression in the spec, such as the
    `coerce: Util.percentToUnit` function reference. Carried through so parsing
    does not fail, but never comparable to a JSON value."""

    __slots__ = ("name",)

    def __init__(self, name: str) -> None:
        self.name = name

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"Opaque({self.name!r})"

    def __eq__(self, other: object) -> bool:
        return isinstance(other, Opaque) and other.name == self.name

    def __hash__(self) -> int:
        return hash(("Opaque", self.name))


def _skip_ws(src: str, i: int) -> int:
    while i < len(src):
        if src[i] in " \t\r\n":
            i += 1
        elif src.startswith("//", i):
            i = src.find("\n", i)
            if i == -1:
                return len(src)
        elif src.startswith("/*", i):
            end = src.find("*/", i)
            if end == -1:
                raise SpecError("unterminated block comment")
            i = end + 2
        else:
            break
    return i


def _parse_value(src: str, i: int):
    i = _skip_ws(src, i)
    if i >= len(src):
        raise SpecError("unexpected end of input")
    ch = src[i]
    if ch == "{":
        obj = {}
        i = _skip_ws(src, i + 1)
        if i < len(src) and src[i] == "}":
            return obj, i + 1
        while True:
            i = _skip_ws(src, i)
            if src[i] == '"':
                key, i = _parse_string(src, i)
            else:
                m = _KEY.match(src, i)
                if not m:
                    raise SpecError(f"bad object key at {i}")
                key, i = m.group(0), m.end()
            i = _skip_ws(src, i)
            if src[i] != ":":
                raise SpecError(f"expected ':' at {i}")
            value, i = _parse_value(src, i + 1)
            obj[key] = value
            i = _skip_ws(src, i)
            if src[i] == ",":
                i += 1
                i = _skip_ws(src, i)
                if src[i] == "}":
                    return obj, i + 1
                continue
            if src[i] == "}":
                return obj, i + 1
            raise SpecError(f"expected ',' or '}}' at {i}")
    if ch == "[":
        arr = []
        i = _skip_ws(src, i + 1)
        if i < len(src) and src[i] == "]":
            return arr, i + 1
        while True:
            value, i = _parse_value(src, i)
            arr.append(value)
            i = _skip_ws(src, i)
            if src[i] == ",":
                i += 1
                i = _skip_ws(src, i)
                if src[i] == "]":
                    return arr, i + 1
                continue
            if src[i] == "]":
                return arr, i + 1
            raise SpecError(f"expected ',' or ']' at {i}")
    if ch == '"':
        return _parse_string(src, i)
    for literal, value in (("true", True), ("false", False), ("null", None)):
        if src.startswith(literal, i):
            return value, i + len(literal)
    m = re.compile(r"-?\d+(\.\d+)?([eE][+-]?\d+)?").match(src, i)
    if m:
        text = m.group(0)
        return (float(text) if ("." in text or "e" in text.lower()) else int(text)), m.end()
    if _KEY.match(src, i):
        return _parse_expression(src, i)
    raise SpecError(f"unsupported literal at {i}: {src[i:i + 40]!r}")


def _parse_expression(src: str, i: int):
    """Skip one bare expression: up to the `,`, `}`, or `]` that ends the value."""
    start, depth = i, 0
    while i < len(src):
        ch = src[i]
        if ch == '"':
            _, i = _parse_string(src, i)
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif ch == "," and depth == 0:
            break
        i += 1
    return Opaque(src[start:i].strip()), i


def _parse_string(src: str, i: int):
    end = i + 1
    out = []
    while end < len(src):
        c = src[end]
        if c == "\\":
            out.append(src[end:end + 2])
            end += 2
            continue
        if c == '"':
            return json.loads("".join(['"'] + out + ['"'])), end + 1
        out.append(c)
        end += 1
    raise SpecError("unterminated string")


def _parse_object(source: str, name: str) -> dict:
    m = re.search(rf"\bvar\s+{name}\s*=\s*", source)
    if not m:
        raise SpecError(f"no {name} assignment found")
    spec, _ = _parse_value(source, m.end())
    if not isinstance(spec, dict):
        raise SpecError(f"{name} is not an object")
    return spec


def parse_spec(source: str) -> dict:
    """Return {key: entry} for the `var SPEC = {...}` object in `source`."""
    return _parse_object(source, "SPEC")


def load_spec(path: pathlib.Path) -> dict:
    """Return {key: entry} for a spec file, following its shared spec.

    DMS assembles a spec as `var SPEC = Util.mergeSpec(Shared.SPEC, LOCAL_SPEC)`,
    where `Shared` names a `.import` relative to the file and local keys win.
    """
    source = path.read_text()
    merged = re.search(
        r"\bvar\s+SPEC\s*=\s*\w+\.mergeSpec\(\s*(\w+)\.SPEC\s*,\s*(\w+)\s*\)", source)
    if not merged:
        return parse_spec(source)
    imported = re.search(rf'^\.import\s+"([^"]+)"\s+as\s+{merged.group(1)}\s*$',
                         source, re.MULTILINE)
    if not imported:
        raise SpecError(f"{path}: no import for {merged.group(1)}")
    shared = (path.parent / imported.group(1)).resolve()
    if not shared.is_file():
        raise SpecError(f"{path}: missing shared spec {shared}")
    return {**load_spec(shared), **_parse_object(source, merged.group(2))}


def _is_computed(value) -> bool:
    if isinstance(value, Opaque):
        return True
    if isinstance(value, dict):
        return any(_is_computed(item) for item in value.values())
    if isinstance(value, list):
        return any(_is_computed(item) for item in value)
    return False


def _persisted(spec: dict) -> dict:
    return {key: entry["def"] for key, entry in spec.items()
            if isinstance(entry, dict) and "def" in entry
            and entry.get("persist") is not False}


def defaults(spec: dict) -> dict:
    """Return {key: default} for every persisted key with a literal default."""
    return {key: value for key, value in _persisted(spec).items()
            if not _is_computed(value)}


def computed_keys(spec: dict) -> set[str]:
    """Return the persisted keys whose default DMS computes in JavaScript."""
    return {key for key, value in _persisted(spec).items() if _is_computed(value)}
