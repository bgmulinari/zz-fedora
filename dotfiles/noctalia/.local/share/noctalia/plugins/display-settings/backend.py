#!/usr/bin/env python3
"""Niri backend for the Noctalia display settings plugin."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import subprocess
import sys
import tempfile
import time
import uuid


TRANSFORMS = {
    "normal",
    "90",
    "180",
    "270",
    "flipped",
    "flipped-90",
    "flipped-180",
    "flipped-270",
}
MODE_RE = re.compile(r"^[1-9][0-9]*x[1-9][0-9]*@[0-9]+(?:\.[0-9]{1,3})?$")
APPLY_GUARD_SECONDS = 120
ROLLBACK_RETRY_SECONDS = 1.0
CONFIG_EVENT_TIMEOUT_SECONDS = 12.0
MANAGED_OUTPUT_NODES = {
    "off",
    "mode",
    "position",
    "scale",
    "transform",
    "variable-refresh-rate",
}


class BackendError(RuntimeError):
    def __init__(self, message: str, *, preview_id: str | None = None):
        super().__init__(message)
        self.preview_id = preview_id


def emit(payload: dict[str, object], exit_code: int = 0) -> None:
    print(json.dumps(payload, separators=(",", ":"), ensure_ascii=False))
    raise SystemExit(exit_code)


def run_command(args: list[str], *, timeout: float = 8) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise BackendError(f"could not run {' '.join(args[:2])}: {exc}") from exc


def run_niri(*args: str, timeout: float = 8) -> subprocess.CompletedProcess[str]:
    result = run_command(["niri", *args], timeout=timeout)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}"
        raise BackendError(f"niri {' '.join(args)} failed: {detail}")
    return result


def normalize_transform(value: object) -> str:
    compact = str(value or "normal").strip().lower().replace("_", "-")
    aliases = {
        "flipped90": "flipped-90",
        "flipped180": "flipped-180",
        "flipped270": "flipped-270",
    }
    compact = aliases.get(compact, compact)
    return compact if compact in TRANSFORMS else "normal"


def format_mode(mode: dict[str, object]) -> str:
    width = int(mode.get("width", 0))
    height = int(mode.get("height", 0))
    refresh = int(mode.get("refresh_rate", 0)) / 1000
    return f"{width}x{height}@{refresh:.3f}"


def normalize_outputs(raw: object) -> list[dict[str, object]]:
    if not isinstance(raw, dict):
        raise BackendError("niri returned an unexpected output document")

    outputs: list[dict[str, object]] = []
    for connector, value in sorted(raw.items()):
        if not isinstance(value, dict):
            continue

        modes = [mode for mode in value.get("modes", []) if isinstance(mode, dict)]
        mode_values = [format_mode(mode) for mode in modes]
        mode_labels = []
        for mode, formatted in zip(modes, mode_values, strict=True):
            label = formatted.replace("@", " @ ") + " Hz"
            if mode.get("is_preferred") is True:
                label += "  • preferred"
            mode_labels.append(label)

        current_index = value.get("current_mode")
        custom_mode = value.get("is_custom_mode") is True
        current_mode = None
        if isinstance(current_index, int) and 0 <= current_index < len(mode_values):
            current_mode = mode_values[current_index]
            if custom_mode:
                mode_labels[current_index] += "  • custom"
        if current_mode is None and mode_values:
            preferred_index = next(
                (index for index, mode in enumerate(modes) if mode.get("is_preferred") is True),
                0,
            )
            current_mode = mode_values[preferred_index]

        logical = value.get("logical")
        enabled = isinstance(logical, dict) and isinstance(current_index, int)
        logical_data = logical if isinstance(logical, dict) else {}
        make = str(value.get("make") or "").strip()
        model = str(value.get("model") or "").strip()
        serial = str(value.get("serial") or "").strip()
        description = " ".join(part for part in (make, model, serial) if part)

        outputs.append(
            {
                "name": str(value.get("name") or connector),
                "description": description or str(connector),
                "enabled": enabled,
                "mode": current_mode or "",
                "custom_mode": custom_mode,
                "mode_values": mode_values,
                "mode_labels": mode_labels,
                "scale": float(logical_data.get("scale", 1.0)),
                "transform": normalize_transform(logical_data.get("transform")),
                "x": int(logical_data.get("x", 0)),
                "y": int(logical_data.get("y", 0)),
                "logical_width": int(logical_data.get("width", 0)),
                "logical_height": int(logical_data.get("height", 0)),
                "vrr_supported": value.get("vrr_supported") is True,
                "vrr_enabled": value.get("vrr_enabled") is True,
            }
        )
    return outputs


def query_outputs() -> list[dict[str, object]]:
    result = run_niri("msg", "-j", "outputs")
    try:
        raw = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise BackendError(f"niri returned invalid JSON: {exc}") from exc
    return normalize_outputs(raw)


def load_draft(path: Path) -> dict[str, object]:
    try:
        draft = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BackendError(f"could not read display draft: {exc}") from exc
    if not isinstance(draft, dict) or not isinstance(draft.get("outputs"), list):
        raise BackendError("display draft must contain an outputs array")
    return draft


def validated_outputs(draft: dict[str, object]) -> list[dict[str, object]]:
    raw_outputs = draft.get("outputs")
    assert isinstance(raw_outputs, list)
    outputs: list[dict[str, object]] = []
    names: set[str] = set()
    enabled_count = 0

    for index, raw in enumerate(raw_outputs):
        if not isinstance(raw, dict):
            raise BackendError(f"output {index + 1} is not an object")
        name = str(raw.get("name") or "")
        if not name or any(char in name for char in "\x00\r\n"):
            raise BackendError(f"output {index + 1} has an invalid connector name")
        if name in names:
            raise BackendError(f"duplicate output connector: {name}")
        names.add(name)

        enabled = raw.get("enabled") is True
        if enabled:
            enabled_count += 1
        mode = str(raw.get("mode") or "")
        if enabled and not MODE_RE.fullmatch(mode):
            raise BackendError(f"{name}: invalid mode {mode!r}")
        try:
            scale = float(raw.get("scale", 1.0))
            x = int(raw.get("x", 0))
            y = int(raw.get("y", 0))
        except (TypeError, ValueError) as exc:
            raise BackendError(f"{name}: scale and position must be numeric") from exc
        if not 0.1 <= scale <= 10:
            raise BackendError(f"{name}: scale must be between 0.1 and 10")
        transform = normalize_transform(raw.get("transform"))

        normalized = dict(raw)
        normalized.update(
            {
                "name": name,
                "enabled": enabled,
                "mode": mode,
                "custom_mode": raw.get("custom_mode") is True,
                "scale": scale,
                "transform": transform,
                "x": x,
                "y": y,
                "vrr_enabled": raw.get("vrr_enabled") is True,
                "vrr_supported": raw.get("vrr_supported") is True,
            }
        )
        outputs.append(normalized)

    if not outputs:
        raise BackendError("no outputs were found")
    if enabled_count == 0:
        raise BackendError("at least one output must remain enabled")
    return outputs


def runtime_dir() -> Path:
    base = Path(os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir())
    directory = base / f"noctalia-display-settings-{os.getuid()}"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    return directory


def token_path() -> Path:
    return runtime_dir() / "preview.json"


def lock_path() -> Path:
    return runtime_dir() / "preview.lock"


@contextmanager
def preview_lock():
    with lock_path().open("a", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def read_preview_token() -> dict[str, object] | None:
    try:
        data = json.loads(token_path().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def cancel_preview(preview_id: str | None = None) -> bool:
    if preview_id is not None:
        data = read_preview_token()
        if data is None or data.get("id") != preview_id:
            return False
    try:
        token_path().unlink(missing_ok=True)
    except OSError as exc:
        raise BackendError(f"could not remove display preview state: {exc}") from exc
    return True


def wait_for_config_loaded(
    process: subprocess.Popen[bytes], buffer: bytearray, timeout: float
) -> bool:
    assert process.stdout is not None
    deadline = time.monotonic() + timeout
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    try:
        while True:
            while b"\n" in buffer:
                raw_line, _, remainder = buffer.partition(b"\n")
                buffer[:] = remainder
                try:
                    event = json.loads(raw_line)
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue
                config_loaded = event.get("ConfigLoaded") if isinstance(event, dict) else None
                if isinstance(config_loaded, dict) and isinstance(config_loaded.get("failed"), bool):
                    return config_loaded["failed"]

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise BackendError("timed out waiting for Niri to finish loading its configuration")
            if not selector.select(remaining):
                raise BackendError("timed out waiting for Niri to finish loading its configuration")
            try:
                chunk = os.read(process.stdout.fileno(), 65536)
            except BlockingIOError:
                continue
            if not chunk:
                raise BackendError("Niri event stream ended before configuration loading completed")
            buffer.extend(chunk)
    finally:
        selector.close()


def stop_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=1)


def reload_persistent_config() -> None:
    validate_persistent_config()
    try:
        stream = subprocess.Popen(
            ["niri", "msg", "-j", "event-stream"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        )
    except OSError as exc:
        raise BackendError(f"could not start the Niri configuration event stream: {exc}") from exc

    assert stream.stdout is not None
    os.set_blocking(stream.stdout.fileno(), False)
    buffer = bytearray()
    try:
        wait_for_config_loaded(stream, buffer, CONFIG_EVENT_TIMEOUT_SECONDS)
        run_niri("msg", "action", "load-config-file")
        if wait_for_config_loaded(stream, buffer, CONFIG_EVENT_TIMEOUT_SECONDS):
            raise BackendError("Niri rejected the persistent configuration during reload")
    finally:
        stop_process(stream)


def reload_and_cancel_preview(preview_id: str) -> bool:
    try:
        reload_persistent_config()
        cancel_preview(preview_id)
    except BackendError:
        return False
    return True


def strip_kdl_comments(content: str) -> str:
    result: list[str] = []
    index = 0
    block_depth = 0
    quote = False
    raw_end: str | None = None

    while index < len(content):
        if block_depth:
            if content.startswith("/*", index):
                block_depth += 1
                index += 2
            elif content.startswith("*/", index):
                block_depth -= 1
                index += 2
            else:
                if content[index] == "\n":
                    result.append("\n")
                index += 1
            continue

        if raw_end is not None:
            if content.startswith(raw_end, index):
                result.append(raw_end)
                index += len(raw_end)
                raw_end = None
            else:
                result.append(content[index])
                index += 1
            continue

        if quote:
            result.append(content[index])
            if content[index] == "\\" and index + 1 < len(content):
                result.append(content[index + 1])
                index += 2
                continue
            if content[index] == '"':
                quote = False
            index += 1
            continue

        raw_match = re.match(r'r(#+)?"', content[index:])
        if raw_match:
            marker = raw_match.group(0)
            hashes = raw_match.group(1) or ""
            result.append(marker)
            index += len(marker)
            raw_end = '"' + hashes
            continue
        if content.startswith("//", index):
            newline = content.find("\n", index)
            if newline == -1:
                break
            result.append("\n")
            index = newline + 1
            continue
        if content.startswith("/*", index):
            block_depth = 1
            index += 2
            continue
        if content[index] == '"':
            quote = True
        result.append(content[index])
        index += 1

    return "".join(result)


def structural_brace_delta(line: str) -> int:
    delta = 0
    index = 0
    quote = False
    raw_end: str | None = None
    while index < len(line):
        if raw_end is not None:
            if line.startswith(raw_end, index):
                index += len(raw_end)
                raw_end = None
            else:
                index += 1
            continue
        if quote:
            if line[index] == "\\" and index + 1 < len(line):
                index += 2
                continue
            if line[index] == '"':
                quote = False
            index += 1
            continue
        raw_match = re.match(r'r(#+)?"', line[index:])
        if raw_match:
            marker = raw_match.group(0)
            raw_end = '"' + (raw_match.group(1) or "")
            index += len(marker)
            continue
        if line[index] == '"':
            quote = True
        elif line[index] == "{":
            delta += 1
        elif line[index] == "}":
            delta -= 1
        index += 1
    return delta


def ensure_safe_existing_config(
    config_path: Path,
    outputs: list[dict[str, object]],
    runtime_disabled_outputs: set[str] | None = None,
) -> None:
    if not config_path.exists():
        return
    try:
        content = config_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise BackendError(f"could not inspect existing Niri display configuration: {exc}") from exc

    output_depth = 0
    ignored_depth = 0
    output_nodes: list[tuple[str, int]] = []
    connected_names = {str(output["name"]).casefold() for output in outputs}
    runtime_disabled_outputs = runtime_disabled_outputs or set()
    configured_names: set[str] = set()
    configured_output_disabled = False
    for line_number, raw_line in enumerate(strip_kdl_comments(content).splitlines(), 1):
        line = raw_line.strip()
        if not line:
            continue
        delta = structural_brace_delta(line)

        if ignored_depth:
            ignored_depth += delta
            continue
        if line.startswith("/-"):
            ignored_depth = max(delta, 0)
            continue

        if output_depth == 0:
            if line.startswith("output ") and delta == 1:
                match = re.fullmatch(r'output\s+("(?:[^"\\]|\\.)*")\s*\{', line)
                if match is None:
                    raise BackendError(
                        f"existing Niri display config has an output name the plugin cannot safely identify on line "
                        f"{line_number}"
                    )
                try:
                    configured_name = json.loads(match.group(1))
                except json.JSONDecodeError as exc:
                    raise BackendError(
                        f"existing Niri display config has an invalid output name on line {line_number}"
                    ) from exc
                normalized_name = configured_name.casefold()
                if normalized_name not in connected_names:
                    raise BackendError(
                        f"existing Niri display config contains output {configured_name!r}, which is not currently "
                        "connected; the plugin will not discard its saved settings"
                    )
                if normalized_name in configured_names:
                    raise BackendError(
                        f"existing Niri display config contains duplicate output {configured_name!r}; "
                        "the plugin cannot safely merge those blocks"
                    )
                configured_names.add(normalized_name)
                configured_output_disabled = normalized_name in runtime_disabled_outputs
                output_nodes = []
                output_depth = 1
                continue
            raise BackendError(
                f"existing Niri display config has an unmanaged top-level node on line {line_number}; "
                "the plugin will not replace this file"
            )

        if line == "}" and delta == -1:
            if any(node == "off" for node, _ in output_nodes) and len(output_nodes) > 1:
                off_line = next(node_line for node, node_line in output_nodes if node == "off")
                raise BackendError(
                    f"existing disabled output keeps additional settings near line {off_line}; Niri IPC does not "
                    "report those inactive values, so the plugin will not replace this file"
                )
            if configured_output_disabled and output_nodes and not any(
                node == "off" for node, _ in output_nodes
            ):
                raise BackendError(
                    "existing Niri display config retains settings for an output that is currently disabled; "
                    "Niri IPC does not report those inactive values, so the plugin will not replace this file"
                )
            output_depth = 0
            configured_output_disabled = False
            continue
        if delta != 0 or ";" in line:
            node = line.split(maxsplit=1)[0]
            raise BackendError(
                f"existing Niri display config uses unsupported output setting {node!r} on line {line_number}; "
                "the plugin will not preview or replace this file"
            )

        node = line.split(maxsplit=1)[0]
        if node == "modeline":
            raise BackendError(
                f"existing Niri display config uses a modeline on line {line_number}; "
                "Niri IPC cannot expose its timings, so the plugin cannot safely preview it"
            )
        if node not in MANAGED_OUTPUT_NODES:
            raise BackendError(
                f"existing Niri display config uses unsupported output setting {node!r} on line {line_number}; "
                "the plugin will not preview or replace this file"
            )
        if node == "variable-refresh-rate" and line not in {
            "variable-refresh-rate",
            "variable-refresh-rate on-demand=false",
        }:
            raise BackendError(
                f"existing Niri display config uses VRR on-demand on line {line_number}; "
                "Niri IPC cannot round-trip that setting"
            )
        output_nodes.append((node, line_number))

    if output_depth != 0 or ignored_depth != 0:
        raise BackendError("existing Niri display config has an unterminated output block")


def apply_outputs(outputs: list[dict[str, object]]) -> None:
    enabled_outputs = [output for output in outputs if output["enabled"] is True]
    disabled_outputs = [output for output in outputs if output["enabled"] is not True]
    for output in enabled_outputs:
        name = str(output["name"])
        run_niri("msg", "output", name, "on")
        mode_action = "custom-mode" if output.get("custom_mode") is True else "mode"
        run_niri("msg", "output", name, mode_action, str(output["mode"]))
        run_niri("msg", "output", name, "scale", f"{float(output['scale']):g}")
        run_niri("msg", "output", name, "transform", str(output["transform"]))
        run_niri(
            "msg",
            "output",
            name,
            "position",
            "set",
            str(int(output["x"])),
            str(int(output["y"])),
        )
        if output.get("vrr_supported") is True:
            run_niri("msg", "output", name, "vrr", "on" if output.get("vrr_enabled") is True else "off")
    for output in disabled_outputs:
        run_niri("msg", "output", str(output["name"]), "off")


def render_kdl(outputs: list[dict[str, object]]) -> str:
    lines = [
        "// Managed by the Noctalia display settings plugin.",
        "// Hardware-specific; do not copy this file between machines.",
        "",
    ]
    for output in outputs:
        name = json.dumps(str(output["name"]), ensure_ascii=False)
        lines.append(f"output {name} {{")
        if output["enabled"] is not True:
            lines.append("    off")
        else:
            custom = " custom=true" if output.get("custom_mode") is True else ""
            lines.append(f"    mode{custom} {json.dumps(str(output['mode']))}")
            lines.append(f"    scale {float(output['scale']):g}")
            if output["transform"] != "normal":
                lines.append(f"    transform {json.dumps(str(output['transform']))}")
            lines.append(f"    position x={int(output['x'])} y={int(output['y'])}")
            if output.get("vrr_enabled") is True:
                lines.append("    variable-refresh-rate")
        lines.extend(("}", ""))
    return "\n".join(lines)


def validate_candidate(path: Path) -> None:
    result = run_command(["niri", "validate", "-c", str(path)], timeout=10)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "validation failed"
        raise BackendError(f"generated Niri configuration is invalid: {detail}")


def validate_persistent_config() -> None:
    result = run_command(["niri", "validate"], timeout=10)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "validation failed"
        raise BackendError(f"current Niri configuration is invalid; cannot preview safely: {detail}")


def write_preview_token(preview_id: str, status: str, *, expires: int | None = None) -> None:
    payload: dict[str, object] = {
        "id": preview_id,
        "status": status,
        "started": int(time.time()),
    }
    if expires is not None:
        payload["expires"] = expires
    try:
        atomic_write(
            token_path(),
            json.dumps(payload, separators=(",", ":")),
        )
    except OSError as exc:
        raise BackendError(f"could not update display preview state: {exc}") from exc


def spawn_watchdog(preview_id: str) -> None:
    try:
        subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "watchdog", preview_id],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
    except OSError as exc:
        cancel_preview()
        reload_persistent_config()
        raise BackendError(f"could not start the display rollback watchdog: {exc}") from exc


def preview(draft_path: Path, config_path: Path, timeout: int) -> dict[str, object]:
    outputs = validated_outputs(load_draft(draft_path))
    config_path = config_path.expanduser().resolve()
    timeout = max(5, min(timeout, 60))
    preview_id = uuid.uuid4().hex
    with preview_lock():
        ensure_safe_existing_config(config_path, outputs)
        runtime_disabled_outputs = {
            str(output["name"]).casefold()
            for output in query_outputs()
            if output.get("enabled") is not True
        }
        ensure_safe_existing_config(config_path, outputs, runtime_disabled_outputs)
        validate_persistent_config()
        cancel_preview()
        write_preview_token(preview_id, "applying")
        spawn_watchdog(preview_id)
        try:
            apply_outputs(outputs)
        except BackendError as apply_error:
            if reload_and_cancel_preview(preview_id):
                raise
            write_preview_token(preview_id, "rollback")
            raise BackendError(
                f"{apply_error}; restoring the persistent display configuration is still pending",
                preview_id=preview_id,
            ) from apply_error
        expires = int(time.time()) + timeout
        try:
            write_preview_token(preview_id, "active", expires=expires)
        except BackendError as state_error:
            if reload_and_cancel_preview(preview_id):
                raise BackendError(
                    f"{state_error}; the persistent display configuration was restored",
                    preview_id=preview_id,
                ) from state_error
            try:
                write_preview_token(preview_id, "rollback")
            except BackendError:
                pass
            raise BackendError(
                f"{state_error}; restoring the persistent display configuration is still pending",
                preview_id=preview_id,
            ) from state_error
    return {"ok": True, "preview_id": preview_id, "timeout": timeout, "expires": expires}


def watchdog(preview_id: str) -> None:
    while True:
        with preview_lock():
            data = read_preview_token()
            if data is None or data.get("id") != preview_id:
                return

            status = data.get("status")
            now = time.time()
            rollback_due = False
            if status == "applying":
                started = data.get("started")
                if isinstance(started, (int, float)) and now - started < APPLY_GUARD_SECONDS:
                    delay = 0.25
                else:
                    rollback_due = True
            elif status == "active":
                expires = data.get("expires")
                if isinstance(expires, (int, float)) and expires > now:
                    delay = min(expires - now, 0.25)
                else:
                    rollback_due = True
            elif status == "rollback":
                rollback_due = True
            else:
                cancel_preview(preview_id)
                return
            if rollback_due:
                if reload_and_cancel_preview(preview_id):
                    return
                delay = ROLLBACK_RETRY_SECONDS
        time.sleep(max(delay, 0.05))


def require_active_preview(preview_id: str) -> None:
    data = read_preview_token()
    if data is None or data.get("id") != preview_id:
        raise BackendError("display preview is no longer active; run Preview again")
    expires = data.get("expires")
    if data.get("status") != "active" or not isinstance(expires, (int, float)) or expires <= time.time():
        if not reload_and_cancel_preview(preview_id):
            write_preview_token(preview_id, "rollback")
            raise BackendError("display preview expired; restoring the persistent configuration is still pending")
        raise BackendError("display preview expired; run Preview again")


def restore_config_file(config_path: Path, backup: Path, had_existing: bool) -> None:
    try:
        if had_existing:
            os.replace(backup, config_path)
        else:
            config_path.unlink(missing_ok=True)
    except OSError as exc:
        raise BackendError(f"could not restore the prior Niri display configuration: {exc}") from exc


def keep(draft_path: Path, config_path: Path, preview_id: str) -> dict[str, object]:
    outputs = validated_outputs(load_draft(draft_path))
    content = render_kdl(outputs)
    config_path = config_path.expanduser().resolve()
    config_path.parent.mkdir(parents=True, exist_ok=True)

    with preview_lock():
        require_active_preview(preview_id)
        ensure_safe_existing_config(config_path, outputs)
        descriptor, candidate_name = tempfile.mkstemp(prefix=f".{config_path.name}.candidate.", dir=config_path.parent)
        candidate = Path(candidate_name)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            validate_candidate(candidate)

            backup = config_path.with_suffix(config_path.suffix + ".previous")
            had_existing = config_path.exists()
            if had_existing:
                shutil.copy2(config_path, backup)
            os.replace(candidate, config_path)

            try:
                aggregate = run_command(["niri", "validate"], timeout=10)
            except BackendError:
                restore_config_file(config_path, backup, had_existing)
                raise
            if aggregate.returncode != 0:
                restore_config_file(config_path, backup, had_existing)
                detail = aggregate.stderr.strip() or aggregate.stdout.strip() or "validation failed"
                raise BackendError(f"complete Niri configuration is invalid: {detail}")

            try:
                reload_persistent_config()
            except BackendError as load_error:
                restore_config_file(config_path, backup, had_existing)
                if reload_and_cancel_preview(preview_id):
                    raise load_error
                write_preview_token(preview_id, "rollback")
                raise BackendError(
                    f"{load_error}; restoring the prior display configuration is still pending"
                ) from load_error
            cancel_preview(preview_id)
            return {"ok": True, "config_path": str(config_path), "backup_path": str(backup) if had_existing else ""}
        finally:
            candidate.unlink(missing_ok=True)


def revert(preview_id: str) -> dict[str, object]:
    with preview_lock():
        data = read_preview_token()
        if data is None:
            return {"ok": True, "already_reverted": True}
        if data.get("id") != preview_id:
            raise BackendError("a different display preview is active")
        try:
            reload_persistent_config()
        except BackendError as load_error:
            write_preview_token(preview_id, "rollback")
            raise BackendError(
                f"{load_error}; restoring the persistent display configuration is still pending",
                preview_id=preview_id,
            ) from load_error
        cancel_preview(preview_id)
    return {"ok": True}


def preview_status(preview_id: str) -> dict[str, object]:
    data = read_preview_token()
    if data is None or data.get("id") != preview_id:
        return {"active": False, "status": "inactive"}
    payload: dict[str, object] = {
        "active": True,
        "id": preview_id,
        "status": str(data.get("status") or "unknown"),
    }
    expires = data.get("expires")
    if isinstance(expires, (int, float)):
        payload["expires"] = expires
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("query")

    preview_parser = subparsers.add_parser("preview")
    preview_parser.add_argument("--draft", type=Path, required=True)
    preview_parser.add_argument("--config", type=Path, required=True)
    preview_parser.add_argument("--timeout", type=int, default=15)

    keep_parser = subparsers.add_parser("keep")
    keep_parser.add_argument("--draft", type=Path, required=True)
    keep_parser.add_argument("--config", type=Path, required=True)
    keep_parser.add_argument("--preview-id", required=True)

    revert_parser = subparsers.add_parser("revert")
    revert_parser.add_argument("--preview-id", required=True)

    watchdog_parser = subparsers.add_parser("watchdog")
    watchdog_parser.add_argument("preview_id")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        if args.command == "query":
            emit({"ok": True, "outputs": query_outputs()})
        if args.command == "preview":
            emit(preview(args.draft, args.config, args.timeout))
        if args.command == "keep":
            emit(keep(args.draft, args.config, args.preview_id))
        if args.command == "revert":
            emit(revert(args.preview_id))
        if args.command == "watchdog":
            watchdog(args.preview_id)
            raise SystemExit(0)
    except BackendError as exc:
        payload: dict[str, object] = {"ok": False, "error": str(exc)}
        expected_preview_id = exc.preview_id
        if expected_preview_id is None and hasattr(args, "preview_id"):
            expected_preview_id = args.preview_id
        if expected_preview_id:
            payload["preview"] = preview_status(expected_preview_id)
        emit(payload, 1)


if __name__ == "__main__":
    main()
