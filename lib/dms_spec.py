"""Parse the DankMaterialShell settings specs into plain Python data.

The specs are JavaScript object literals shipped with the shell
(`Common/settings/{SettingsSpec,SessionSpec}.js`). They are the only place
DMS records a default for every key, so promoting live settings into the ZZ
seed needs them to tell a deliberate change apart from an untouched default.

Only the literal subset the specs actually use is supported: objects, arrays,
double-quoted strings, numbers, booleans, and null. Anything else raises, so a
future spec that outgrows this parser fails loudly instead of silently
reporting wrong defaults.
"""

from __future__ import annotations

import json
import re

_KEY = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")


class SpecError(RuntimeError):
    pass


class Opaque:
    """A bare identifier in the spec, such as the `coerce: percentToUnit`
    function reference. Carried through so parsing does not fail, but never
    comparable to a JSON value."""

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
    m = _KEY.match(src, i)
    if m:
        return Opaque(m.group(0)), m.end()
    raise SpecError(f"unsupported literal at {i}: {src[i:i + 40]!r}")


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


def parse_spec(source: str) -> dict:
    """Return {key: entry} for the `var SPEC = {...}` object in `source`."""
    m = re.search(r"\bvar\s+SPEC\s*=\s*", source)
    if not m:
        raise SpecError("no SPEC assignment found")
    spec, _ = _parse_value(source, m.end())
    if not isinstance(spec, dict):
        raise SpecError("SPEC is not an object")
    return spec


def defaults(spec: dict) -> dict:
    """Return {key: default} for every persisted key in `spec`."""
    out = {}
    for key, entry in spec.items():
        if not isinstance(entry, dict) or "def" not in entry:
            continue
        if entry.get("persist") is False:
            continue
        value = entry["def"]
        if isinstance(value, Opaque):
            raise SpecError(f"{key} has a non-literal default: {value!r}")
        out[key] = value
    return out
